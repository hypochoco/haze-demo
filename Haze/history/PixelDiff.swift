//
//  PixelDiff.swift
//  Haze — history
//

import Metal

struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var isEmpty: Bool { width <= 0 || height <= 0 }
    var byteCount: Int { width * height * 4 }

    static func fromBounds(minX: Float, minY: Float, maxX: Float, maxY: Float,
                           canvasWidth: Int, canvasHeight: Int) -> PixelRect? {
        let x0 = max(0, Int(minX.rounded(.down)))
        let y0 = max(0, Int(minY.rounded(.down)))
        let x1 = min(canvasWidth, Int(maxX.rounded(.up)))
        let y1 = min(canvasHeight, Int(maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    func tiled(_ tile: Int) -> [PixelRect] {
        let t = max(1, tile)
        var out: [PixelRect] = []
        var ty = y
        while ty < y + height {
            let h = min(t, y + height - ty)
            var tx = x
            while tx < x + width {
                let w = min(t, x + width - tx)
                out.append(PixelRect(x: tx, y: ty, width: w, height: h))
                tx += t
            }
            ty += t
        }
        return out
    }
}

struct TileDiff {
    let rect: PixelRect
    let before: PixelPayload
    let after: PixelPayload
    var byteCount: Int { before.byteCount + after.byteCount }
}

struct PixelDiff {
    let tiles: [TileDiff]

    var byteCount: Int { tiles.reduce(0) { $0 + $1.byteCount } }
    var isEmpty: Bool { tiles.isEmpty }

    @MainActor
    func restoreBefore(to target: PixelTarget, render: RenderContext, canvas: Canvas) {
        for t in tiles { render.resources.write(target, rect: t.rect, bytes: t.before.raw(), canvas: canvas) }
    }

    @MainActor
    func restoreAfter(to target: PixelTarget, render: RenderContext, canvas: Canvas) {
        for t in tiles { render.resources.write(target, rect: t.rect, bytes: t.after.raw(), canvas: canvas) }
    }
}
