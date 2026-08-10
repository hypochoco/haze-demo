//
//  StrokeCompositor.swift
//  Haze — render
//

import Metal

@MainActor
final class StrokeCompositor {
    private let ctx: RenderContext
    private var below: MTLTexture?
    private var above: MTLTexture?
    private var visual: MTLTexture?
    private var effMask: MTLTexture?
    private var activeOpacity: Float = 1
    private var activeBlend: BlendMode = .normal
    private var maskTex: MTLTexture?
    private var paintingMask = false
    private(set) var isActive = false

    init(ctx: RenderContext) { self.ctx = ctx }

    func begin(canvas: Canvas, activeID: LayerID, maskTex: MTLTexture?, paintingMask: Bool) -> Bool {
        end()
        guard let idx = canvas.nodes.firstIndex(where: { $0.id == activeID }),
              case .layer(let active) = canvas.nodes[idx] else { return false }
        let aboveNodes = Array(canvas.nodes[(idx + 1)...])
        guard aboveNodes.allSatisfy({ $0.blend.isNormal }) else { return false }
        let belowNodes = Array(canvas.nodes[0..<idx])

        let w = canvas.width, h = canvas.height
        let fmt = canvas.colorMode.mtlPixelFormat
        if !belowNodes.isEmpty {
            guard let t = ctx.acquireCompositeTemp(width: w, height: h, format: fmt) else { return false }
            Compositor.composite(Canvas(width: w, height: h, nodes: belowNodes), into: t, ctx: ctx)
            below = t
        }
        if !aboveNodes.isEmpty {
            guard let t = ctx.acquireCompositeTemp(width: w, height: h, format: fmt) else { end(); return false }
            Compositor.composite(Canvas(width: w, height: h, nodes: aboveNodes), into: t, ctx: ctx)
            above = t
        }
        activeOpacity = active.opacity
        activeBlend = active.blend
        self.maskTex = maskTex
        self.paintingMask = paintingMask
        guard let v = SingleTextureLayerStore.makeTexture(ctx.device, w, h, format: fmt) else { end(); return false }
        visual = v
        if paintingMask, maskTex != nil {
            guard let m = SingleTextureLayerStore.makeTexture(ctx.device, w, h, format: fmt) else { end(); return false }
            effMask = m
        }
        isActive = true
        return true
    }

    func frame(into target: MTLTexture, activeTex: MTLTexture,
               scratch: MTLTexture?, previewOpacity: Float, dirty: PixelRect?,
               selectionMask: MTLTexture? = nil, erase: Bool = false) {
        guard isActive, let visual else { return }
        let w = target.width, h = target.height
        let scis = dirty.flatMap { scissor($0, w: w, h: h) }
        guard let cb = ctx.queue.makeCommandBuffer() else { return }
        let set = ctx.pipelines(for: target.pixelFormat)

        let activeSource: MTLTexture
        let modMask: MTLTexture?
        if paintingMask {
            activeSource = activeTex
            if let base = maskTex, let effMask {
                buildEffMask(cb: cb, base: base, scratch: scratch, opacity: previewOpacity,
                             erase: erase, selection: selectionMask, into: effMask, set: set)
                modMask = effMask
            } else {
                modMask = nil
            }
        } else {
            buildVisual(cb: cb, activeTex: activeTex, scratch: scratch, opacity: previewOpacity,
                        erase: erase, selection: selectionMask, into: visual, scis: scis, set: set)
            activeSource = visual
            modMask = maskTex
        }

        let sp = MTLRenderPassDescriptor()
        sp.colorAttachments[0].texture = target
        sp.colorAttachments[0].loadAction = dirty == nil ? .clear : .load
        sp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        sp.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: sp) {
            if let scis { enc.setScissorRect(scis) }
            enc.setFragmentSamplerState(ctx.sampler, index: 0)
            if let below {
                enc.setRenderPipelineState(set.replace)
                ctx.encodeCompositeQuad(enc, src: below, opacity: 1)
                drawActive(enc, set: set, src: activeSource, mask: modMask, overBackdrop: true)
            } else {
                drawActive(enc, set: set, src: activeSource, mask: modMask, overBackdrop: false)
            }
            if let above {
                enc.setRenderPipelineState(set.composite)
                ctx.encodeCompositeQuad(enc, src: above, opacity: 1)
            }
            enc.endEncoding()
        }
        cb.commit()
    }

    private func drawActive(_ enc: MTLRenderCommandEncoder, set: RenderContext.Pipelines,
                            src: MTLTexture, mask: MTLTexture?, overBackdrop: Bool) {
        if let mask {
            if overBackdrop {
                if activeBlend.isNormal {
                    enc.setRenderPipelineState(set.compositeMasked)
                    ctx.encodeMaskedQuad(enc, src: src, mask: mask, opacity: activeOpacity)
                } else {
                    enc.setRenderPipelineState(set.compositeBlendMasked)
                    ctx.encodeBlendedMaskedQuad(enc, src: src, mask: mask, opacity: activeOpacity, mode: activeBlend.gpuCode)
                }
            } else {
                enc.setRenderPipelineState(set.compositeMaskedReplace)
                ctx.encodeMaskedQuad(enc, src: src, mask: mask, opacity: activeOpacity)
            }
        } else {
            if overBackdrop {
                if activeBlend.isNormal {
                    enc.setRenderPipelineState(set.composite)
                    ctx.encodeCompositeQuad(enc, src: src, opacity: activeOpacity)
                } else {
                    enc.setRenderPipelineState(set.blend)
                    ctx.encodeBlendedQuad(enc, src: src, opacity: activeOpacity, mode: activeBlend.gpuCode)
                }
            } else {
                enc.setRenderPipelineState(set.replace)
                ctx.encodeCompositeQuad(enc, src: src, opacity: activeOpacity)
            }
        }
    }

    private func buildVisual(cb: MTLCommandBuffer, activeTex: MTLTexture, scratch: MTLTexture?,
                             opacity: Float, erase: Bool, selection: MTLTexture?,
                             into visual: MTLTexture, scis: MTLScissorRect?, set: RenderContext.Pipelines) {
        let vp = MTLRenderPassDescriptor()
        vp.colorAttachments[0].texture = visual
        vp.colorAttachments[0].loadAction = .clear
        vp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        vp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: vp) else { return }
        if let scis { enc.setScissorRect(scis) }
        enc.setFragmentSamplerState(ctx.sampler, index: 0)
        enc.setRenderPipelineState(set.composite)
        ctx.encodeCompositeQuad(enc, src: activeTex, opacity: 1)
        applyScratch(enc, set: set, scratch: scratch, opacity: opacity, erase: erase, selection: selection)
        enc.endEncoding()
    }

    private func buildEffMask(cb: MTLCommandBuffer, base: MTLTexture, scratch: MTLTexture?,
                              opacity: Float, erase: Bool, selection: MTLTexture?,
                              into effMask: MTLTexture, set: RenderContext.Pipelines) {
        let mp = MTLRenderPassDescriptor()
        mp.colorAttachments[0].texture = effMask
        mp.colorAttachments[0].loadAction = .clear
        mp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        mp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: mp) else { return }
        enc.setFragmentSamplerState(ctx.sampler, index: 0)
        enc.setRenderPipelineState(set.replace)
        ctx.encodeCompositeQuad(enc, src: base, opacity: 1)
        applyScratch(enc, set: set, scratch: scratch, opacity: opacity, erase: erase, selection: selection)
        enc.endEncoding()
    }

    private func applyScratch(_ enc: MTLRenderCommandEncoder, set: RenderContext.Pipelines,
                              scratch: MTLTexture?, opacity: Float, erase: Bool, selection: MTLTexture?) {
        guard let scratch else { return }
        switch (erase, selection) {
        case (false, let m?): enc.setRenderPipelineState(set.compositeMasked); ctx.encodeMaskedQuad(enc, src: scratch, mask: m, opacity: opacity)
        case (false, nil):    enc.setRenderPipelineState(set.composite);       ctx.encodeCompositeQuad(enc, src: scratch, opacity: opacity)
        case (true,  let m?): enc.setRenderPipelineState(set.eraseMasked);      ctx.encodeMaskedQuad(enc, src: scratch, mask: m, opacity: opacity)
        case (true,  nil):    enc.setRenderPipelineState(set.erase);            ctx.encodeCompositeQuad(enc, src: scratch, opacity: opacity)
        }
    }

    func end() {
        if let below { ctx.releaseCompositeTemp(below) }
        if let above { ctx.releaseCompositeTemp(above) }
        below = nil; above = nil; visual = nil; effMask = nil
        maskTex = nil; paintingMask = false; isActive = false
    }

    private func scissor(_ r: PixelRect, w: Int, h: Int) -> MTLScissorRect? {
        let x0 = max(0, r.x), y0 = max(0, r.y)
        let x1 = min(w, r.x + r.width), y1 = min(h, r.y + r.height)
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
