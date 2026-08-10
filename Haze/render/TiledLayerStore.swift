//
//  TiledLayerStore.swift
//  Haze — render
//

import Metal
import Foundation

@MainActor
final class TiledLayerStore: LayerStore {
    private struct TileKey: Hashable { let col: Int; let row: Int }

    private let device: MTLDevice
    let colorMode: ColorMode
    private(set) var width: Int
    private(set) var height: Int
    private let tileSize: Int
    private var tiles: [TileKey: MTLTexture] = [:]

    private var bpp: Int { colorMode.bytesPerPixel }

    init?(device: MTLDevice, width: Int, height: Int, tileSize: Int, colorMode: ColorMode = .default) {
        guard tileSize > 0 else { return nil }
        self.device = device
        self.colorMode = colorMode
        self.width = width
        self.height = height
        self.tileSize = tileSize
    }

    var byteCount: Int { tiles.values.reduce(0) { $0 + $1.width * $1.height * bpp } }

    var allocatedTileCount: Int { tiles.count }

    // MARK: - Tile geometry

    private func tileRect(_ key: TileKey) -> PixelRect {
        let x = key.col * tileSize, y = key.row * tileSize
        return PixelRect(x: x, y: y, width: min(tileSize, width - x), height: min(tileSize, height - y))
    }

    private func keys(overlapping rect: PixelRect) -> [TileKey] {
        guard !rect.isEmpty else { return [] }
        let x0 = max(0, rect.x), y0 = max(0, rect.y)
        let x1 = min(width, rect.x + rect.width), y1 = min(height, rect.y + rect.height)
        guard x1 > x0, y1 > y0 else { return [] }
        var out: [TileKey] = []
        for r in (y0 / tileSize)...((y1 - 1) / tileSize) {
            for c in (x0 / tileSize)...((x1 - 1) / tileSize) { out.append(TileKey(col: c, row: r)) }
        }
        return out
    }

    private func intersection(_ a: PixelRect, _ b: PixelRect) -> PixelRect {
        let x0 = max(a.x, b.x), y0 = max(a.y, b.y)
        let x1 = min(a.x + a.width, b.x + b.width), y1 = min(a.y + a.height, b.y + b.height)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func makeTile(_ key: TileKey) -> MTLTexture? {
        let rect = tileRect(key)
        guard let tex = SingleTextureLayerStore.makeTexture(device, rect.width, rect.height,
                                                            format: colorMode.mtlPixelFormat) else { return nil }
        SingleTextureLayerStore.fill(tex)
        return tex
    }

    // MARK: - CPU region read/write

    func read(_ rect: PixelRect) -> [UInt8]? {
        guard !rect.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: rect.width * rect.height * bpp)
        for key in keys(overlapping: rect) {
            guard let tex = tiles[key] else { continue }
            let tr = tileRect(key)
            let inter = intersection(rect, tr)
            guard !inter.isEmpty else { continue }
            var block = [UInt8](repeating: 0, count: inter.width * inter.height * bpp)
            block.withUnsafeMutableBytes { raw in
                tex.getBytes(raw.baseAddress!, bytesPerRow: inter.width * bpp,
                             from: MTLRegionMake2D(inter.x - tr.x, inter.y - tr.y, inter.width, inter.height),
                             mipmapLevel: 0)
            }
            insert(block, into: &out, dstStride: rect.width, dstX: inter.x - rect.x, dstY: inter.y - rect.y,
                   w: inter.width, h: inter.height)
        }
        return out
    }

    func write(_ rect: PixelRect, bytes: [UInt8]) {
        guard !rect.isEmpty, bytes.count == rect.width * rect.height * bpp else { return }
        for key in keys(overlapping: rect) {
            let tr = tileRect(key)
            let inter = intersection(rect, tr)
            guard !inter.isEmpty else { continue }
            let tex: MTLTexture
            if let t = tiles[key] { tex = t } else { guard let t = makeTile(key) else { continue }; tiles[key] = t; tex = t }
            let block = extract(bytes, srcStride: rect.width, srcX: inter.x - rect.x, srcY: inter.y - rect.y,
                                w: inter.width, h: inter.height)
            block.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(inter.x - tr.x, inter.y - tr.y, inter.width, inter.height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: inter.width * bpp)
            }
        }
    }

    // MARK: - GPU

    func encodeComposite(into enc: MTLRenderCommandEncoder, opacity: Float, blend: BlendMode, ctx: RenderContext) {
        for (key, tex) in tiles {
            let q = quad(for: tileRect(key))
            if blend.isNormal { ctx.encodeCompositeQuad(enc, src: tex, opacity: opacity, quad: q) }
            else { ctx.encodeBlendedQuad(enc, src: tex, opacity: opacity, mode: blend.gpuCode, quad: q) }
        }
    }

    func blendScratch(_ scratch: MTLTexture, dirty: PixelRect, opacity: Float, mask: MTLTexture?, erase: Bool, ctx: RenderContext) {
        for key in keys(overlapping: dirty) {
            let tr = tileRect(key)
            let tex: MTLTexture
            if let t = tiles[key] { tex = t } else { guard let t = makeTile(key) else { continue }; tiles[key] = t; tex = t }
            let uv = SIMD4<Float>(Float(tr.x) / Float(width), Float(tr.y) / Float(height),
                                  Float(tr.x + tr.width) / Float(width), Float(tr.y + tr.height) / Float(height))
            let quad = RenderContext.CompositeVSUniform(dstRect: [-1, -1, 1, 1], srcUV: uv)
            switch (erase, mask) {
            case (false, let m?): ctx.blendRegionMasked(scratch, mask: m, into: tex, opacity: opacity, quad: quad)
            case (false, nil):    ctx.blendRegion(scratch, into: tex, opacity: opacity, quad: quad)
            case (true,  let m?): ctx.eraseRegionMasked(scratch, mask: m, into: tex, opacity: opacity, quad: quad)
            case (true,  nil):    ctx.eraseRegion(scratch, into: tex, opacity: opacity, quad: quad)
            }
        }
    }

    func materialize(ctx: RenderContext) -> MTLTexture? {
        guard let dst = SingleTextureLayerStore.makeTexture(device, width, height,
                                                            format: colorMode.mtlPixelFormat) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = ctx.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setRenderPipelineState(ctx.pipelines(for: dst.pixelFormat).composite)
        encodeComposite(into: enc, opacity: 1, blend: .normal, ctx: ctx)
        enc.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return dst
    }

    // MARK: - Resize

    func cropExtend(toWidth newW: Int, toHeight newH: Int, offset: (dx: Int, dy: Int)) {
        let (dx, dy) = offset
        let x0 = max(0, dx), y0 = max(0, dy)
        let x1 = min(newW, dx + width), y1 = min(newH, dy + height)
        let copyW = x1 - x0, copyH = y1 - y0
        var overlap: [UInt8]? = nil
        if copyW > 0 && copyH > 0 {
            overlap = read(PixelRect(x: x0 - dx, y: y0 - dy, width: copyW, height: copyH))
        }
        tiles.removeAll(); width = newW; height = newH
        if let overlap, copyW > 0, copyH > 0 {
            write(PixelRect(x: x0, y: y0, width: copyW, height: copyH), bytes: overlap)
        }
    }

    func resample(toWidth newW: Int, toHeight newH: Int, ctx: RenderContext) {
        guard let full = materialize(ctx: ctx),
              let scaled = ctx.resampleTexture(full, toWidth: newW, toHeight: newH,
                                               format: colorMode.mtlPixelFormat) else { return }
        var bytes = [UInt8](repeating: 0, count: newW * newH * bpp)
        bytes.withUnsafeMutableBytes { raw in
            scaled.getBytes(raw.baseAddress!, bytesPerRow: newW * bpp,
                            from: MTLRegionMake2D(0, 0, newW, newH), mipmapLevel: 0)
        }
        tiles.removeAll(); width = newW; height = newH
        write(PixelRect(x: 0, y: 0, width: newW, height: newH), bytes: bytes)
    }

    func reallocateBlank(toWidth newW: Int, toHeight newH: Int) {
        tiles.removeAll(); width = newW; height = newH
    }

    // MARK: - Helpers

    private func quad(for r: PixelRect) -> RenderContext.CompositeVSUniform {
        let W = Float(width), H = Float(height)
        let minX = Float(r.x) / W * 2 - 1
        let maxX = Float(r.x + r.width) / W * 2 - 1
        let maxY = 1 - Float(r.y) / H * 2
        let minY = 1 - Float(r.y + r.height) / H * 2
        return RenderContext.CompositeVSUniform(dstRect: [minX, minY, maxX, maxY], srcUV: [0, 0, 1, 1])
    }

    private func extract(_ src: [UInt8], srcStride: Int, srcX: Int, srcY: Int, w: Int, h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * bpp)
        let rowBytes = w * bpp
        out.withUnsafeMutableBytes { dst in
            src.withUnsafeBytes { s in
                for row in 0..<h {
                    let sOff = ((srcY + row) * srcStride + srcX) * bpp
                    memcpy(dst.baseAddress!.advanced(by: row * rowBytes), s.baseAddress!.advanced(by: sOff), rowBytes)
                }
            }
        }
        return out
    }

    private func insert(_ block: [UInt8], into dst: inout [UInt8], dstStride: Int, dstX: Int, dstY: Int, w: Int, h: Int) {
        let rowBytes = w * bpp
        dst.withUnsafeMutableBytes { d in
            block.withUnsafeBytes { b in
                for row in 0..<h {
                    let dOff = ((dstY + row) * dstStride + dstX) * bpp
                    memcpy(d.baseAddress!.advanced(by: dOff), b.baseAddress!.advanced(by: row * rowBytes), rowBytes)
                }
            }
        }
    }
}
