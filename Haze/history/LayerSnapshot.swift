//
//  LayerSnapshot.swift
//  Haze — history
//

import Metal

@MainActor
struct LayerSnapshot {
    struct Tile { let rect: PixelRect; let payload: PixelPayload }
    let tiles: [Tile]

    var byteCount: Int { tiles.reduce(0) { $0 + $1.payload.byteCount } }

    static func capture(_ target: PixelTarget, canvas: Canvas,
                        render: RenderContext, tileSize: Int) -> LayerSnapshot {
        let full = PixelRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        var tiles: [Tile] = []
        for rect in full.tiled(tileSize) {
            guard let bytes = render.resources.read(target, rect: rect, canvas: canvas) else { continue }
            if bytes.contains(where: { $0 != 0 }) {
                tiles.append(Tile(rect: rect, payload: PixelPayload(raw: bytes)))
            }
        }
        return LayerSnapshot(tiles: tiles)
    }

    static func capture(texture tex: MTLTexture, tileSize: Int) -> LayerSnapshot {
        let bpp = tex.pixelFormat.haze_bytesPerPixel
        let full = PixelRect(x: 0, y: 0, width: tex.width, height: tex.height)
        var tiles: [Tile] = []
        for rect in full.tiled(tileSize) {
            var bytes = [UInt8](repeating: 0, count: rect.width * rect.height * bpp)
            bytes.withUnsafeMutableBytes { raw in
                tex.getBytes(raw.baseAddress!, bytesPerRow: rect.width * bpp,
                             from: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height), mipmapLevel: 0)
            }
            if bytes.contains(where: { $0 != 0 }) {
                tiles.append(Tile(rect: rect, payload: PixelPayload(raw: bytes)))
            }
        }
        return LayerSnapshot(tiles: tiles)
    }

    func restore(_ target: PixelTarget, render: RenderContext, canvas: Canvas) {
        for tile in tiles {
            render.resources.write(target, rect: tile.rect, bytes: tile.payload.raw(), canvas: canvas)
        }
    }
}
