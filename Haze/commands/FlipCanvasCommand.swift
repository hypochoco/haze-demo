//
//  FlipCanvasCommand.swift
//  Haze — commands
//

import Metal

struct FlipCanvasCommand: Command {
    let horizontal: Bool
    let layerIDs: [LayerID]

    var title: String { horizontal ? "Flip Canvas Horizontally" : "Flip Canvas Vertically" }
    var affectedLayers: [LayerID] { layerIDs }

    func apply(_ ctx: CommandContext) { flipAll(ctx) }
    func revert(_ ctx: CommandContext) { flipAll(ctx) }

    private func flipAll(_ ctx: CommandContext) {
        let w = ctx.canvas.width, h = ctx.canvas.height
        let bpp = ctx.canvas.colorMode.bytesPerPixel
        let full = PixelRect(x: 0, y: 0, width: w, height: h)
        func flipTarget(_ target: PixelTarget) {
            guard let store = ctx.render.resources.store(for: target, canvas: ctx.canvas),
                  let bytes = store.read(full) else { return }
            store.write(full, bytes: Self.flip(bytes, w: w, h: h, bpp: bpp, horizontal: horizontal))
        }
        for id in layerIDs { flipTarget(.layer(id)) }
    }

    static func flip(_ src: [UInt8], w: Int, h: Int, bpp: Int, horizontal: Bool) -> [UInt8] {
        let rowBytes = w * bpp
        var out = [UInt8](repeating: 0, count: src.count)
        if horizontal {
            for y in 0..<h {
                let row = y * rowBytes
                for x in 0..<w {
                    let s = row + (w - 1 - x) * bpp
                    let d = row + x * bpp
                    for b in 0..<bpp { out[d + b] = src[s + b] }
                }
            }
        } else {
            for y in 0..<h {
                let s = (h - 1 - y) * rowBytes
                let d = y * rowBytes
                out.replaceSubrange(d..<d + rowBytes, with: src[s..<s + rowBytes])
            }
        }
        return out
    }
}
