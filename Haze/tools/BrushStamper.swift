//
//  BrushStamper.swift
//  Haze — tools
//

import Metal
import simd

struct BrushUniforms {
    var ortho: simd_float4x4
    var color: SIMD4<Float>
    var center: SIMD2<Float>
    var radius: Float
    var hardness: Float
    var flow: Float
    var opacityCeil: Float = 1
    var angle: Float = 0
    var roundness: Float = 1
    var footprint: Float = 1
    var tipContent: Float = 1
}

enum BrushStamper {

    static let footprintScale: Float = 1.4142136

    @MainActor
    static func stamp(_ dabs: [Dab], color: SIMD4<Float>, hardness: Float,
                      tip: MTLTexture? = nil, roundness: Float = 1,
                      into tex: MTLTexture, ceiling: MTLTexture? = nil, ctx: RenderContext) {
        guard !dabs.isEmpty,
              let scissor = scissorRect(for: dabs, scale: tip != nil ? footprintScale : 1,
                                        width: tex.width, height: tex.height) else { return }
        let ortho = simd_float4x4.imageOrthographic(width: Float(tex.width), height: Float(tex.height))
        let rn = max(0.05, min(1, roundness))
        let fp: Float = tip != nil ? footprintScale : 1
        let tc: Float = tip != nil ? BrushTipCatalog.tipContentFrac : 1

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store

        guard let cb = ctx.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(tip != nil ? ctx.pipelines(for: tex.pixelFormat).brushTextured
                                              : ctx.pipelines(for: tex.pixelFormat).brushAccum)
        if let tip {
            enc.setFragmentTexture(tip, index: 0)
            enc.setFragmentSamplerState(ctx.tipSampler, index: 0)
        }
        enc.setScissorRect(scissor)
        for dab in dabs {
            var u = BrushUniforms(ortho: ortho, color: color,
                                  center: dab.center, radius: max(0.5, dab.radius),
                                  hardness: hardness, flow: dab.flow,
                                  angle: dab.angle, roundness: rn, footprint: fp, tipContent: tc)
            enc.setVertexBytes(&u, length: MemoryLayout<BrushUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<BrushUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()

        if let ceiling,
           let scis = scissorRect(for: dabs, scale: fp, width: ceiling.width, height: ceiling.height) {
            let cpass = MTLRenderPassDescriptor()
            cpass.colorAttachments[0].texture = ceiling
            cpass.colorAttachments[0].loadAction = .load
            cpass.colorAttachments[0].storeAction = .store
            let cortho = simd_float4x4.imageOrthographic(width: Float(ceiling.width), height: Float(ceiling.height))
            if let cenc = cb.makeRenderCommandEncoder(descriptor: cpass) {
                cenc.setRenderPipelineState(tip != nil ? ctx.brushTexturedCeilingPipeline : ctx.brushCeilingPipeline)
                if let tip {
                    cenc.setFragmentTexture(tip, index: 0)
                    cenc.setFragmentSamplerState(ctx.tipSampler, index: 0)
                }
                cenc.setScissorRect(scis)
                for dab in dabs {
                    var u = BrushUniforms(ortho: cortho, color: color,
                                          center: dab.center, radius: max(0.5, dab.radius),
                                          hardness: hardness, flow: dab.flow, opacityCeil: dab.opacity,
                                          angle: dab.angle, roundness: rn, footprint: fp, tipContent: tc)
                    cenc.setVertexBytes(&u, length: MemoryLayout<BrushUniforms>.stride, index: 0)
                    cenc.setFragmentBytes(&u, length: MemoryLayout<BrushUniforms>.stride, index: 0)
                    cenc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                cenc.endEncoding()
            }
        }
        cb.commit()
    }

    private static func scissorRect(for dabs: [Dab], scale: Float = 1, width: Int, height: Int) -> MTLScissorRect? {
        var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for d in dabs {
            let r = max(0.5, d.radius) * scale
            minX = min(minX, d.center.x - r); minY = min(minY, d.center.y - r)
            maxX = max(maxX, d.center.x + r); maxY = max(maxY, d.center.y + r)
        }
        let x0 = max(0, Int(minX.rounded(.down))), y0 = max(0, Int(minY.rounded(.down)))
        let x1 = min(width, Int(maxX.rounded(.up))), y1 = min(height, Int(maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
