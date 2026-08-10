//
//  MaskSnapshot.swift
//  Haze — history
//

@MainActor
struct MaskSnapshot {
    struct Tile { let rect: PixelRect; let payload: PixelPayload }

    let state: SelectionState
    let tiles: [Tile]

    var byteCount: Int { tiles.reduce(0) { $0 + $1.payload.byteCount } }

    static func capture(_ canvas: Canvas, render: RenderContext, tileSize: Int,
                        within: PixelRect? = nil) -> MaskSnapshot {
        guard let store = render.resources.selection(for: canvas) else {
            return MaskSnapshot(state: canvas.pixelSelection, tiles: [])
        }
        return MaskSnapshot(state: canvas.pixelSelection,
                            tiles: nonEmptyTiles(store, tileSize: tileSize, within: within))
    }

    static func nonEmptyTiles(_ store: SelectionStore, tileSize: Int, within: PixelRect? = nil) -> [Tile] {
        let full = PixelRect(x: 0, y: 0, width: store.width, height: store.height)
        var region = within ?? full
        let x0 = max(0, region.x), y0 = max(0, region.y)
        let x1 = min(store.width, region.x + region.width), y1 = min(store.height, region.y + region.height)
        region = PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        guard !region.isEmpty else { return [] }
        var tiles: [Tile] = []
        for rect in region.tiled(tileSize) {
            guard let bytes = store.read(rect) else { continue }
            if bytes.contains(where: { $0 != 0 }) {
                tiles.append(Tile(rect: rect, payload: PixelPayload(raw: bytes)))
            }
        }
        return tiles
    }

    func restore(_ ctx: CommandContext) {
        ctx.canvas.pixelSelection = state
        guard let store = ctx.render.resources.selection(for: ctx.canvas) else { return }
        store.clear()
        for t in tiles { store.write(t.rect, bytes: t.payload.raw()) }
    }
}
