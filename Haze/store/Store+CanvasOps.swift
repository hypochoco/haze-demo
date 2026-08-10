//
//  Store+CanvasOps.swift
//  Haze — store
//

import Metal
import simd

extension Store {
    func flipCanvas(horizontal: Bool) {
        guard let canvas = requireCanvas(horizontal ? "Flip Canvas Horizontally" : "Flip Canvas Vertically")
        else { return }
        let ids = canvas.layers.map(\.id)
        guard !ids.isEmpty else { return }
        perform(FlipCanvasCommand(horizontal: horizontal, layerIDs: ids))
    }

    func sampleColor(atCanvas p: SIMD2<Float>) -> SIMD4<Float>? {
        guard let canvas = activeCanvas else { return nil }
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < canvas.width, y < canvas.height else { return nil }
        guard let target = render.compositeTexture(width: canvas.width, height: canvas.height) else { return nil }
        Compositor.composite(canvas, into: target, ctx: render)
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: 4,
                            from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        }
        let a = Float(px[3])
        if a == 0 { return [0, 0, 0, 1] }
        return [min(Float(px[2]) / a, 1), min(Float(px[1]) / a, 1), min(Float(px[0]) / a, 1), 1]
    }
}
