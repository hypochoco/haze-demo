//
//  RenderContext.swift
//  Haze — render
//

@preconcurrency import Metal
import simd
import OSLog
import CoreGraphics
import Foundation

@MainActor
final class RenderContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let resources: ResourceCache
    let sampler: MTLSamplerState
    let tipSampler: MTLSamplerState
    let compositePipeline: MTLRenderPipelineState
    let blendPipeline: MTLRenderPipelineState
    let presentPipeline: MTLRenderPipelineState
    let brushAccumPipeline: MTLRenderPipelineState
    let brushCeilingPipeline: MTLRenderPipelineState
    let brushTexturedCeilingPipeline: MTLRenderPipelineState

    private let library: MTLLibrary

    struct Pipelines {
        let composite: MTLRenderPipelineState
        let blend: MTLRenderPipelineState
        let brushAccum: MTLRenderPipelineState
        let brushTextured: MTLRenderPipelineState
        let compositeMasked: MTLRenderPipelineState
        let compositeBlendMasked: MTLRenderPipelineState
        let compositeMaskedReplace: MTLRenderPipelineState
        let compositeQuad: MTLRenderPipelineState
        let erase: MTLRenderPipelineState
        let eraseMasked: MTLRenderPipelineState
        let replace: MTLRenderPipelineState
        let scratchResolve: MTLRenderPipelineState
    }
    private var pipelineCache: [UInt: Pipelines] = [:]

    private var compositeTex: MTLTexture?
    private var scratchTex: MTLTexture?
    private var ceilingTex: MTLTexture?
    private var resolvedTex: MTLTexture?
    private var maskPreviewTex: MTLTexture?
    private var tempPool: [MTLTexture] = []
    private var tipTextureCache: [UUID: MTLTexture] = [:]

    static let tipLodMaxClamp: Float = 2.0

    nonisolated static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    nonisolated static let ceilingFormat: MTLPixelFormat = .r16Float

    func pipelines(for format: MTLPixelFormat) -> Pipelines {
        if let p = pipelineCache[format.rawValue] { return p }
        let p = Pipelines(
            composite: Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .over, format: format)!,
            blend: Self.makePipeline(device, library, "composite_vertex", "composite_blend_frag", blend: .none, format: format)!,
            brushAccum: Self.makePipeline(device, library, "brush_vertex", "brush_frag", blend: .over, format: format)!,
            brushTextured: Self.makePipeline(device, library, "brush_vertex", "brush_textured_frag", blend: .over, format: format)!,
            compositeMasked: Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .over, format: format)!,
            compositeBlendMasked: Self.makePipeline(device, library, "composite_vertex", "composite_blend_masked_frag", blend: .none, format: format)!,
            compositeMaskedReplace: Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .none, format: format)!,
            compositeQuad: Self.makePipeline(device, library, "composite_quad_vertex", "composite_frag", blend: .over, format: format)!,
            erase: Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .erase, format: format)!,
            eraseMasked: Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .erase, format: format)!,
            replace: Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .none, format: format)!,
            scratchResolve: Self.makePipeline(device, library, "composite_vertex", "scratch_resolve_frag", blend: .none, format: format)!)
        pipelineCache[format.rawValue] = p
        return p
    }

    func acquireCompositeTemp(width: Int, height: Int,
                              format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        if let i = tempPool.firstIndex(where: { $0.width == width && $0.height == height && $0.pixelFormat == format }) {
            return tempPool.remove(at: i)
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, width), height: max(1, height), mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]; d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    func releaseCompositeTemp(_ tex: MTLTexture) { tempPool.append(tex) }

    private enum BlendKind { case none, over, max, erase }

    struct CompositeVSUniform {
        var dstRect: SIMD4<Float>
        var srcUV: SIMD4<Float>
        nonisolated static let full = CompositeVSUniform(dstRect: [-1, -1, 1, 1], srcUV: [0, 0, 1, 1])
    }

    struct QuadVSUniform {
        var p0: SIMD2<Float>
        var p1: SIMD2<Float>
        var p2: SIMD2<Float>
        var p3: SIMD2<Float>
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            Log.gpu.error("Metal unavailable")
            return nil
        }
        self.device = device
        self.queue = queue
        self.resources = ResourceCache(device: device)
        self.library = library

        let samp = MTLSamplerDescriptor()
        samp.minFilter = .linear; samp.magFilter = .linear
        samp.sAddressMode = .clampToEdge; samp.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samp) else { return nil }
        self.sampler = sampler

        let tsamp = MTLSamplerDescriptor()
        tsamp.minFilter = .linear; tsamp.magFilter = .linear; tsamp.mipFilter = .linear
        tsamp.sAddressMode = .clampToEdge; tsamp.tAddressMode = .clampToEdge
        tsamp.lodMaxClamp = RenderContext.tipLodMaxClamp
        guard let tipSampler = device.makeSamplerState(descriptor: tsamp) else { return nil }
        self.tipSampler = tipSampler

        let fmt = RenderContext.pixelFormat
        guard let comp = Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .over, format: fmt),
              let blend = Self.makePipeline(device, library, "composite_vertex", "composite_blend_frag", blend: .none, format: fmt),
              let pres = Self.makePipeline(device, library, "present_vertex", "present_frag", blend: .over, format: fmt),
              let brush = Self.makePipeline(device, library, "brush_vertex", "brush_frag", blend: .over, format: fmt),
              let brushTex = Self.makePipeline(device, library, "brush_vertex", "brush_textured_frag", blend: .over, format: fmt),
              let masked = Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .over, format: fmt),
              let blendMasked = Self.makePipeline(device, library, "composite_vertex", "composite_blend_masked_frag", blend: .none, format: fmt),
              let maskedReplace = Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .none, format: fmt),
              let quad = Self.makePipeline(device, library, "composite_quad_vertex", "composite_frag", blend: .over, format: fmt),
              let erase = Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .erase, format: fmt),
              let eraseMasked = Self.makePipeline(device, library, "composite_vertex", "composite_masked_frag", blend: .erase, format: fmt),
              let replace = Self.makePipeline(device, library, "composite_vertex", "composite_frag", blend: .none, format: fmt),
              let resolve = Self.makePipeline(device, library, "composite_vertex", "scratch_resolve_frag", blend: .none, format: fmt),
              let brushCeiling = Self.makePipeline(device, library, "brush_vertex", "brush_ceiling_frag", blend: .max, format: RenderContext.ceilingFormat),
              let brushTexCeiling = Self.makePipeline(device, library, "brush_vertex", "brush_textured_ceiling_frag", blend: .max, format: RenderContext.ceilingFormat) else {
            Log.gpu.error("Pipeline creation failed")
            return nil
        }
        self.compositePipeline = comp
        self.blendPipeline = blend
        self.presentPipeline = pres
        self.brushAccumPipeline = brush
        self.brushCeilingPipeline = brushCeiling
        self.brushTexturedCeilingPipeline = brushTexCeiling
        self.pipelineCache[fmt.rawValue] = Pipelines(composite: comp, blend: blend, brushAccum: brush, brushTextured: brushTex, compositeMasked: masked, compositeBlendMasked: blendMasked, compositeMaskedReplace: maskedReplace, compositeQuad: quad, erase: erase, eraseMasked: eraseMasked, replace: replace, scratchResolve: resolve)
    }

    nonisolated private static func makePipeline(_ device: MTLDevice, _ library: MTLLibrary,
                                                 _ vfn: String, _ ffn: String,
                                                 blend: BlendKind, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vfn)
        d.fragmentFunction = library.makeFunction(name: ffn)
        let c = d.colorAttachments[0]!
        c.pixelFormat = format
        switch blend {
        case .none:
            c.isBlendingEnabled = false
        case .over:
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .max:
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .max; c.alphaBlendOperation = .max
        case .erase:
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .zero; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    // MARK: - Cached targets

    func compositeTexture(width: Int, height: Int,
                          format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        cached(&compositeTex, width: width, height: height, format: format)
    }

    func scratchTexture(width: Int, height: Int,
                        format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        cached(&scratchTex, width: width, height: height, format: format)
    }

    func ceilingTexture(width: Int, height: Int) -> MTLTexture? {
        cached(&ceilingTex, width: width, height: height, format: RenderContext.ceilingFormat)
    }

    func resolvedScratchTexture(width: Int, height: Int,
                                format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        cached(&resolvedTex, width: width, height: height, format: format)
    }

    func maskPreviewTexture(width: Int, height: Int,
                            format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        cached(&maskPreviewTex, width: width, height: height, format: format)
    }

    func buildEffectiveMask(base: MTLTexture, scratch: MTLTexture?, opacity: Float, erase: Bool,
                            selection: MTLTexture?, into dst: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        let set = pipelines(for: dst.pixelFormat)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setRenderPipelineState(set.replace)
        encodeCompositeQuad(enc, src: base, opacity: 1)
        if let scratch {
            switch (erase, selection) {
            case (false, let m?): enc.setRenderPipelineState(set.compositeMasked); encodeMaskedQuad(enc, src: scratch, mask: m, opacity: opacity)
            case (false, nil):    enc.setRenderPipelineState(set.composite);       encodeCompositeQuad(enc, src: scratch, opacity: opacity)
            case (true,  let m?): enc.setRenderPipelineState(set.eraseMasked);      encodeMaskedQuad(enc, src: scratch, mask: m, opacity: opacity)
            case (true,  nil):    enc.setRenderPipelineState(set.erase);            encodeCompositeQuad(enc, src: scratch, opacity: opacity)
            }
        }
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func resolveScratch(_ scratch: MTLTexture, ceiling: MTLTexture, into dst: MTLTexture, dirty: PixelRect?) {
        let w = dst.width, h = dst.height
        let scis: MTLScissorRect? = dirty.flatMap {
            let x0 = max(0, $0.x), y0 = max(0, $0.y)
            let x1 = min(w, $0.x + $0.width), y1 = min(h, $0.y + $0.height)
            return (x1 > x0 && y1 > y0) ? MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : nil
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = dirty == nil ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let scis { enc.setScissorRect(scis) }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).scratchResolve)
        var u = CompositeVSUniform.full
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(scratch, index: 0)
        enc.setFragmentTexture(ceiling, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.commit()
    }

    private func cached(_ slot: inout MTLTexture?, width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        if let t = slot, t.width == width, t.height == height, t.pixelFormat == format { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, width), height: max(1, height), mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .shared
        slot = device.makeTexture(descriptor: d)
        return slot
    }

    // MARK: - Passes

    func encodeCompositeQuad(_ enc: MTLRenderCommandEncoder, src: MTLTexture, opacity: Float,
                             quad: CompositeVSUniform = .full) {
        var u = quad
        var op = opacity
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentBytes(&op, length: MemoryLayout<Float>.size, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    func encodeMaskedQuad(_ enc: MTLRenderCommandEncoder, src: MTLTexture, mask: MTLTexture,
                          opacity: Float, quad: CompositeVSUniform = .full) {
        var u = quad
        var op = opacity
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentTexture(mask, index: 1)
        enc.setFragmentBytes(&op, length: MemoryLayout<Float>.size, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    func encodeBlendedQuad(_ enc: MTLRenderCommandEncoder, src: MTLTexture, opacity: Float,
                           mode: UInt32, quad: CompositeVSUniform = .full) {
        var u = quad
        var op = opacity
        var m = mode
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentBytes(&op, length: MemoryLayout<Float>.size, index: 0)
        enc.setFragmentBytes(&m, length: MemoryLayout<UInt32>.size, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    func encodeBlendedMaskedQuad(_ enc: MTLRenderCommandEncoder, src: MTLTexture, mask: MTLTexture,
                                 opacity: Float, mode: UInt32, quad: CompositeVSUniform = .full) {
        var u = quad
        var op = opacity
        var m = mode
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentTexture(mask, index: 1)
        enc.setFragmentBytes(&op, length: MemoryLayout<Float>.size, index: 0)
        enc.setFragmentBytes(&m, length: MemoryLayout<UInt32>.size, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    func drawOver(_ tex: MTLTexture, into dst: MTLTexture, canvasRect r: PixelRect, canvasW: Int, canvasH: Int) {
        guard !r.isEmpty else { return }
        let W = Float(canvasW), H = Float(canvasH)
        let minX = Float(r.x) / W * 2 - 1
        let maxX = Float(r.x + r.width) / W * 2 - 1
        let maxY = 1 - Float(r.y) / H * 2
        let minY = 1 - Float(r.y + r.height) / H * 2
        let quad = CompositeVSUniform(dstRect: [minX, minY, maxX, maxY], srcUV: [0, 0, 1, 1])
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).composite)
        encodeCompositeQuad(enc, src: tex, opacity: 1, quad: quad)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func drawOverQuad(_ tex: MTLTexture, into dst: MTLTexture,
                      topLeft tl: SIMD2<Float>, topRight tr: SIMD2<Float>,
                      bottomLeft bl: SIMD2<Float>, bottomRight br: SIMD2<Float>,
                      canvasW: Int, canvasH: Int) {
        let W = Float(canvasW), H = Float(canvasH)
        func ndc(_ p: SIMD2<Float>) -> SIMD2<Float> { [p.x / W * 2 - 1, 1 - p.y / H * 2] }
        var u = QuadVSUniform(p0: ndc(bl), p1: ndc(br), p2: ndc(tl), p3: ndc(tr))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).compositeQuad)
        enc.setVertexBytes(&u, length: MemoryLayout<QuadVSUniform>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        var op: Float = 1
        enc.setFragmentBytes(&op, length: MemoryLayout<Float>.size, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func flush() {
        guard let cb = queue.makeCommandBuffer() else { return }
        cb.commit()
        cb.waitUntilCompleted()
    }

    func bakeMasked(layer: MTLTexture, mask: MTLTexture, into dst: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).compositeMasked)
        encodeMaskedQuad(enc, src: layer, mask: mask, opacity: 1)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func fill(_ tex: MTLTexture, premul c: SIMD4<Double>) {        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: c.x, green: c.y, blue: c.z, alpha: c.w)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func blend(_ src: MTLTexture, into dst: MTLTexture, opacity: Float) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).composite)
        encodeCompositeQuad(enc, src: src, opacity: opacity)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func blendRegion(_ src: MTLTexture, into dst: MTLTexture, opacity: Float, quad: CompositeVSUniform) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).composite)
        encodeCompositeQuad(enc, src: src, opacity: opacity, quad: quad)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func blendMasked(_ src: MTLTexture, mask: MTLTexture, into dst: MTLTexture, opacity: Float) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).compositeMasked)
        encodeMaskedQuad(enc, src: src, mask: mask, opacity: opacity)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func blendRegionMasked(_ src: MTLTexture, mask: MTLTexture, into dst: MTLTexture,
                           opacity: Float, quad: CompositeVSUniform) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines(for: dst.pixelFormat).compositeMasked)
        encodeMaskedQuad(enc, src: src, mask: mask, opacity: opacity, quad: quad)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func eraseRegionMasked(_ src: MTLTexture, mask: MTLTexture, into dst: MTLTexture,
                           opacity: Float, quad: CompositeVSUniform) {
        erasePass(dst) { enc in
            enc.setRenderPipelineState(self.pipelines(for: dst.pixelFormat).eraseMasked)
            self.encodeMaskedQuad(enc, src: src, mask: mask, opacity: opacity, quad: quad)
        }
    }

    func erase(_ src: MTLTexture, into dst: MTLTexture, opacity: Float) {
        erasePass(dst) { enc in
            enc.setRenderPipelineState(self.pipelines(for: dst.pixelFormat).erase)
            self.encodeCompositeQuad(enc, src: src, opacity: opacity)
        }
    }

    func eraseRegion(_ src: MTLTexture, into dst: MTLTexture, opacity: Float, quad: CompositeVSUniform) {
        erasePass(dst) { enc in
            enc.setRenderPipelineState(self.pipelines(for: dst.pixelFormat).erase)
            self.encodeCompositeQuad(enc, src: src, opacity: opacity, quad: quad)
        }
    }

    func eraseMasked(_ src: MTLTexture, mask: MTLTexture, into dst: MTLTexture, opacity: Float) {
        erasePass(dst) { enc in
            enc.setRenderPipelineState(self.pipelines(for: dst.pixelFormat).eraseMasked)
            self.encodeMaskedQuad(enc, src: src, mask: mask, opacity: opacity)
        }
    }

    private func erasePass(_ dst: MTLTexture, _ body: (MTLRenderCommandEncoder) -> Void) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        body(enc)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    func renderThumbnail(_ target: PixelTarget, canvas: Canvas, maxDim: Int,
                         completion: @escaping (CGImage?) -> Void) {
        func deliver(_ image: CGImage?) { DispatchQueue.main.async { completion(image) } }
        guard let src = resources.store(for: target, canvas: canvas)?.materialize(ctx: self) else { deliver(nil); return }

        let aspect = Double(canvas.width) / Double(max(1, canvas.height))
        let tw = aspect >= 1 ? maxDim : max(1, Int((Double(maxDim) * aspect).rounded()))
        let th = aspect >= 1 ? max(1, Int((Double(maxDim) / aspect).rounded())) : maxDim
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: RenderContext.pixelFormat, width: tw, height: th, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
        guard let dst = device.makeTexture(descriptor: d) else { deliver(nil); return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { deliver(nil); return }
        enc.setRenderPipelineState(compositePipeline)
        encodeCompositeQuad(enc, src: src, opacity: 1)
        enc.endEncoding()
        cb.addCompletedHandler { _ in
            let image = RenderContext.cgImage(from: dst)
            DispatchQueue.main.async { completion(image) }
        }
        cb.commit()
    }

    func renderBrushSample(width: Int, height: Int, dabs: [Dab],
                           color: SIMD4<Float>, hardness: Float, opacity: Float,
                           tipID: UUID? = nil, roundness: Float = 1) -> CGImage? {
        guard width > 0, height > 0,
              let scratch = SingleTextureLayerStore.makeTexture(device, width, height),
              let dst = SingleTextureLayerStore.makeTexture(device, width, height) else { return nil }
        SingleTextureLayerStore.fill(scratch)
        SingleTextureLayerStore.fill(dst)
        let tip = tipID.flatMap { tipTexture(for: $0) }
        BrushStamper.stamp(dabs, color: color, hardness: hardness, tip: tip, roundness: roundness, into: scratch, ctx: self)
        blend(scratch, into: dst, opacity: opacity)
        return RenderContext.cgImage(from: dst)
    }

    func tipCoverage(for id: UUID) -> (bytes: [UInt8], width: Int)? {
        BrushTipCatalog.coverage(for: id)
    }

    func tipTexture(for id: UUID) -> MTLTexture? {
        if let t = tipTextureCache[id] { return t }
        guard let (bytes, w) = BrushTipCatalog.coverage(for: id) else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: w, mipmapped: true)
        d.usage = [.shaderRead]; d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        bytes.withUnsafeBytes { p in
            tex.replace(region: MTLRegionMake2D(0, 0, w, w), mipmapLevel: 0,
                        withBytes: p.baseAddress!, bytesPerRow: w)
        }
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        tipTextureCache[id] = tex
        return tex
    }

    func dropTipTexture(_ id: UUID) { tipTextureCache[id] = nil }

    func resampleTexture(_ src: MTLTexture, toWidth w: Int, toHeight h: Int,
                         format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, w), height: max(1, h), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
        guard let dst = device.makeTexture(descriptor: d) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setRenderPipelineState(pipelines(for: format).composite)
        encodeCompositeQuad(enc, src: src, opacity: 1)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return dst
    }

    nonisolated static func readBytes(from tex: MTLTexture) -> [UInt8] {
        let w = tex.width, h = tex.height, bpp = tex.pixelFormat.haze_bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: w * h * bpp)
        bytes.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: w * bpp,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    nonisolated private static func cgImage(from tex: MTLTexture) -> CGImage? {
        let w = tex.width, h = tex.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bytes = readBytes(from: tex)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        if tex.pixelFormat == .rgba16Unorm {
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.byteOrder16Little.rawValue)
            return CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64,
                           bytesPerRow: w * 8, space: space, bitmapInfo: info, provider: provider,
                           decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
