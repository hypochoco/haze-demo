//
//  LayerStore.swift
//  Haze — render
//

import Metal

@MainActor
protocol LayerStore: AnyObject {
    var width: Int { get }
    var height: Int { get }
    var byteCount: Int { get }

    func read(_ rect: PixelRect) -> [UInt8]?
    func write(_ rect: PixelRect, bytes: [UInt8])

    func encodeComposite(into enc: MTLRenderCommandEncoder, opacity: Float, blend: BlendMode, ctx: RenderContext)
    func blendScratch(_ scratch: MTLTexture, dirty: PixelRect, opacity: Float, mask: MTLTexture?, erase: Bool, ctx: RenderContext)
    func materialize(ctx: RenderContext) -> MTLTexture?

    func cropExtend(toWidth: Int, toHeight: Int, offset: (dx: Int, dy: Int))
    func resample(toWidth: Int, toHeight: Int, ctx: RenderContext)
    func reallocateBlank(toWidth: Int, toHeight: Int)
}

extension LayerStore {
    func blendScratch(_ scratch: MTLTexture, dirty: PixelRect, opacity: Float, mask: MTLTexture?, ctx: RenderContext) {
        blendScratch(scratch, dirty: dirty, opacity: opacity, mask: mask, erase: false, ctx: ctx)
    }
}

@MainActor
final class SingleTextureLayerStore: LayerStore {
    private let device: MTLDevice
    let colorMode: ColorMode
    private(set) var width: Int
    private(set) var height: Int
    private var texture: MTLTexture

    private var bpp: Int { colorMode.bytesPerPixel }
    var byteCount: Int { width * height * bpp }

    init?(device: MTLDevice, width: Int, height: Int, colorMode: ColorMode = .default) {
        guard let tex = Self.makeInitialized(device, width, height, format: colorMode.mtlPixelFormat) else { return nil }
        self.device = device
        self.colorMode = colorMode
        self.width = width
        self.height = height
        self.texture = tex
    }

    func read(_ rect: PixelRect) -> [UInt8]? {
        guard !rect.isEmpty else { return nil }
        var bytes = [UInt8](repeating: 0, count: rect.width * rect.height * bpp)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: rect.width * bpp,
                             from: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height), mipmapLevel: 0)
        }
        return bytes
    }

    func write(_ rect: PixelRect, bytes: [UInt8]) {
        guard !rect.isEmpty, bytes.count == rect.width * rect.height * bpp else { return }
        bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: rect.width * bpp)
        }
    }

    func encodeComposite(into enc: MTLRenderCommandEncoder, opacity: Float, blend: BlendMode, ctx: RenderContext) {
        if blend.isNormal { ctx.encodeCompositeQuad(enc, src: texture, opacity: opacity) }
        else { ctx.encodeBlendedQuad(enc, src: texture, opacity: opacity, mode: blend.gpuCode) }
    }

    func blendScratch(_ scratch: MTLTexture, dirty: PixelRect, opacity: Float, mask: MTLTexture?, erase: Bool, ctx: RenderContext) {
        switch (erase, mask) {
        case (false, let m?): ctx.blendMasked(scratch, mask: m, into: texture, opacity: opacity)
        case (false, nil):    ctx.blend(scratch, into: texture, opacity: opacity)
        case (true,  let m?): ctx.eraseMasked(scratch, mask: m, into: texture, opacity: opacity)
        case (true,  nil):    ctx.erase(scratch, into: texture, opacity: opacity)
        }
    }

    func materialize(ctx: RenderContext) -> MTLTexture? { texture }

    func cropExtend(toWidth newW: Int, toHeight newH: Int, offset: (dx: Int, dy: Int)) {
        guard let newTex = Self.makeInitialized(device, newW, newH, format: colorMode.mtlPixelFormat) else { return }
        let oldW = texture.width, oldH = texture.height
        let (dx, dy) = offset
        let x0 = max(0, dx), y0 = max(0, dy)
        let x1 = min(newW, dx + oldW), y1 = min(newH, dy + oldH)
        let copyW = x1 - x0, copyH = y1 - y0
        if copyW > 0 && copyH > 0 {
            let srcX = x0 - dx, srcY = y0 - dy
            var buf = [UInt8](repeating: 0, count: copyW * copyH * bpp)
            buf.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: copyW * bpp,
                                 from: MTLRegionMake2D(srcX, srcY, copyW, copyH), mipmapLevel: 0)
            }
            buf.withUnsafeBytes { raw in
                newTex.replace(region: MTLRegionMake2D(x0, y0, copyW, copyH), mipmapLevel: 0,
                               withBytes: raw.baseAddress!, bytesPerRow: copyW * bpp)
            }
        }
        texture = newTex; width = newW; height = newH
    }

    func resample(toWidth newW: Int, toHeight newH: Int, ctx: RenderContext) {
        guard let dst = ctx.resampleTexture(texture, toWidth: newW, toHeight: newH,
                                            format: colorMode.mtlPixelFormat) else { return }
        texture = dst; width = newW; height = newH
    }

    func reallocateBlank(toWidth newW: Int, toHeight newH: Int) {
        guard let tex = Self.makeInitialized(device, newW, newH, format: colorMode.mtlPixelFormat) else { return }
        texture = tex; width = newW; height = newH
    }

    // MARK: - Allocation
    static func makeTexture(_ device: MTLDevice, _ w: Int, _ h: Int,
                            format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, w), height: max(1, h), mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }

    static func makeInitialized(_ device: MTLDevice, _ w: Int, _ h: Int,
                                format: MTLPixelFormat = RenderContext.pixelFormat) -> MTLTexture? {
        guard let tex = makeTexture(device, w, h, format: format) else { return nil }
        fill(tex)
        return tex
    }

    static func fill(_ tex: MTLTexture) {
        let w = tex.width, h = tex.height, bpp = tex.pixelFormat.haze_bytesPerPixel
        let bytes = [UInt8](repeating: 0, count: w * h * bpp)
        bytes.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: w * bpp)
        }
    }
}
