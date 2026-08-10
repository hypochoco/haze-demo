//
//  Compositor.swift
//  Haze — render
//

import Metal

@MainActor
enum Compositor {

    @MainActor
    static func composite(_ canvas: Canvas, into target: MTLTexture, ctx: RenderContext) {
        Log.interval("composite") {
            render(canvas.nodes, into: target, ctx: ctx, canvas: canvas)
            #if DEBUG
            PerfCounters.composites += 1
            #endif
        }
    }

    @MainActor
    private static func render(_ nodes: [LayerNode], into target: MTLTexture,
                               ctx: RenderContext, canvas: Canvas) {
        let fmt = target.pixelFormat
        let set = ctx.pipelines(for: fmt)
        let w = target.width, h = target.height

        var groupTemps: [LayerID: MTLTexture] = [:]
        for node in nodes {
            if case .group(let g) = node, g.isVisible, g.opacity > 0, !g.children.isEmpty {
                guard let temp = ctx.acquireCompositeTemp(width: w, height: h, format: fmt) else { continue }
                render(g.children, into: temp, ctx: ctx, canvas: canvas)
                groupTemps[g.id] = temp
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store

        if let cb = ctx.queue.makeCommandBuffer(),
           let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            enc.setFragmentSamplerState(ctx.sampler, index: 0)
            for node in nodes {
                switch node {
                case .layer(let l) where l.isVisible && l.opacity > 0:
                    enc.setRenderPipelineState(l.blend.isNormal ? set.composite : set.blend)
                    ctx.resources.store(for: .layer(l.id), canvas: canvas)?
                        .encodeComposite(into: enc, opacity: l.opacity, blend: l.blend, ctx: ctx)
                case .group(let g):
                    if let temp = groupTemps[g.id] {
                        enc.setRenderPipelineState(g.blend.isNormal ? set.composite : set.blend)
                        if g.blend.isNormal {
                            ctx.encodeCompositeQuad(enc, src: temp, opacity: g.opacity)
                        } else {
                            ctx.encodeBlendedQuad(enc, src: temp, opacity: g.opacity, mode: g.blend.gpuCode)
                        }
                    }
                default:
                    break
                }
            }
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }

        for temp in groupTemps.values { ctx.releaseCompositeTemp(temp) }
    }
}
