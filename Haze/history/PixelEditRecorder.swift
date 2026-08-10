//
//  PixelEditRecorder.swift
//  Haze — history
//

@MainActor
enum PixelEditRecorder {
    static func capture(target: PixelTarget, rect: PixelRect, canvas: Canvas,
                        render: RenderContext, tileSize: Int, title: String,
                        apply: () -> Void) -> PixelEditCommand? {
        let tiles = rect.tiled(tileSize)
        let befores = tiles.map { render.resources.read(target, rect: $0, canvas: canvas) }

        apply()

        var diffs: [TileDiff] = []
        diffs.reserveCapacity(tiles.count)
        for (i, tile) in tiles.enumerated() {
            guard let before = befores[i],
                  let after = render.resources.read(target, rect: tile, canvas: canvas) else { continue }
            if before != after {
                diffs.append(TileDiff(rect: tile,
                                      before: PixelPayload(raw: before),
                                      after: PixelPayload(raw: after)))
            }
        }
        guard !diffs.isEmpty else { return nil }
        return PixelEditCommand(title: title, target: target, diff: PixelDiff(tiles: diffs))
    }
}
