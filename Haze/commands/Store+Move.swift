//
//  Store+Move.swift
//  Haze — commands
//

import Metal
import simd

struct FloatingSelection {
    let layerID: LayerID
    let sourceBounds: PixelRect
    var offset: SIMD2<Float>
    let floatTex: MTLTexture
    let erasedBytes: [UInt8]
    let srcBeforeBytes: [UInt8]
    let maskBefore: MaskSnapshot
}

struct FloatingLift {
    let layerID: LayerID
    let sourceBounds: PixelRect
    let floatTex: MTLTexture
    let erasedBytes: [UInt8]
    let srcBeforeBytes: [UInt8]
    let maskBefore: MaskSnapshot
}

extension Store {

    var isFloating: Bool { floating != nil }

    var floatingOffset: SIMD2<Float>? { floating?.offset }

    func floatingPreview() -> (tex: MTLTexture, rect: PixelRect)? {
        guard let f = floating else { return nil }
        let dx = Int(f.offset.x.rounded()), dy = Int(f.offset.y.rounded())
        return (f.floatTex, PixelRect(x: f.sourceBounds.x + dx, y: f.sourceBounds.y + dy,
                                      width: f.sourceBounds.width, height: f.sourceBounds.height))
    }

    func liftSelection(_ toolName: String) -> FloatingLift? {
        guard let canvas = requireCanvas(toolName) else { return nil }
        guard canvas.pixelSelection.isActive else {
            notices.post("Make a selection to \(toolName.lowercased())", .warning); return nil
        }
        guard let lid = canvas.selectedLayerID,
              let store = render.resources.store(for: .layer(lid), canvas: canvas),
              let maskStore = render.resources.selection(for: canvas) else { return nil }
        let b = canvas.pixelSelection.bounds
        let bpp = canvas.colorMode.bytesPerPixel
        guard !b.isEmpty, let layerBytes = store.read(b), let maskBytes = maskStore.read(b) else { return nil }

        let n = b.width * b.height
        var floatB = [UInt8](repeating: 0, count: n * bpp)
        var erased = [UInt8](repeating: 0, count: n * bpp)
        if bpp == 8 {
            for i in 0..<n {
                let cov = Float(maskBytes[i]) / 255
                let m = maskBytes[i]
                for c in 0..<4 {
                    let o = i * 8 + c * 2
                    let v = Float(UInt16(layerBytes[o]) | (UInt16(layerBytes[o + 1]) << 8))
                    Self.putLE16(&floatB, o, v * cov)
                    if m == 0 { erased[o] = layerBytes[o]; erased[o + 1] = layerBytes[o + 1] }
                }
            }
        } else {
            for i in 0..<n {
                let cov = Float(maskBytes[i]) / 255
                let m = maskBytes[i]
                for c in 0..<4 {
                    let v = Float(layerBytes[i * 4 + c])
                    floatB[i * 4 + c] = UInt8((v * cov).rounded())
                    if m == 0 { erased[i * 4 + c] = layerBytes[i * 4 + c] }
                }
            }
        }

        guard let tex = SingleTextureLayerStore.makeTexture(render.device, b.width, b.height,
                                                            format: canvas.colorMode.mtlPixelFormat) else { return nil }
        floatB.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, b.width, b.height), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: b.width * bpp)
        }
        let maskBefore = MaskSnapshot.capture(canvas, render: render, tileSize: config.tileSize, within: b)
        store.write(b, bytes: erased)

        return FloatingLift(layerID: lid, sourceBounds: b, floatTex: tex,
                            erasedBytes: erased, srcBeforeBytes: layerBytes, maskBefore: maskBefore)
    }

    func beginFloatingMove() {
        guard floating == nil else { return }
        guard let lift = liftSelection("Move") else { return }
        floating = FloatingSelection(layerID: lift.layerID, sourceBounds: lift.sourceBounds, offset: .zero,
                                     floatTex: lift.floatTex, erasedBytes: lift.erasedBytes,
                                     srcBeforeBytes: lift.srcBeforeBytes, maskBefore: lift.maskBefore)
        floatingVersion &+= 1
        bumpContent([lift.layerID])
    }

    func setFloatingOffset(_ offset: SIMD2<Float>) {
        guard floating != nil else { return }
        floating?.offset = offset
        floatingVersion &+= 1
    }

    func cancelFloatingMove() {
        guard let f = floating, let canvas = activeCanvas,
              let store = render.resources.store(for: .layer(f.layerID), canvas: canvas) else { floating = nil; return }
        store.write(f.sourceBounds, bytes: f.srcBeforeBytes)
        floating = nil
        floatingVersion &+= 1
        bumpContent([f.layerID])
    }

    func commitFloatingMove() {
        guard let f = floating, let canvas = activeCanvas,
              let store = render.resources.store(for: .layer(f.layerID), canvas: canvas),
              let maskStore = render.resources.selection(for: canvas) else { floating = nil; return }
        floating = nil
        let dx = Int(f.offset.x.rounded()), dy = Int(f.offset.y.rounded())
        let src = f.sourceBounds
        let W = canvas.width, H = canvas.height

        let destFull = PixelRect(x: src.x + dx, y: src.y + dy, width: src.width, height: src.height)
        let union = clampRect(boundingRect(src, destFull), W, H)

        store.write(src, bytes: f.srcBeforeBytes)

        let target = PixelTarget.layer(f.layerID)
        let pe = PixelEditRecorder.capture(target: target, rect: union, canvas: canvas,
                                           render: render, tileSize: config.tileSize, title: "Move Selection") {
            store.write(src, bytes: f.erasedBytes)
            stampFloat(f, into: store, dx: dx, dy: dy, canvasW: W, canvasH: H)
        }

        let maskAfter = translateMask(maskStore, canvas: canvas, dx: dx, dy: dy)

        floatingVersion &+= 1
        bumpContent([f.layerID])

        guard let pe else { return }
        record(MoveSelectionCommand(target: target, diff: pe.diff,
                                    maskBefore: f.maskBefore, maskAfter: maskAfter))
    }

    // MARK: - Helpers

    private func stampFloat(_ f: FloatingSelection, into store: LayerStore,
                            dx: Int, dy: Int, canvasW: Int, canvasH: Int) {
        let src = f.sourceBounds
        let dest = clampRect(PixelRect(x: src.x + dx, y: src.y + dy, width: src.width, height: src.height),
                             canvasW, canvasH)
        guard !dest.isEmpty, var dst = store.read(dest) else { return }
        let floatBytes = RenderContext.readBytes(from: f.floatTex)
        let bpp = f.floatTex.pixelFormat.haze_bytesPerPixel
        let sixteen = bpp == 8
        for y in 0..<dest.height {
            for x in 0..<dest.width {
                let fx = (dest.x + x) - (src.x + dx)
                let fy = (dest.y + y) - (src.y + dy)
                guard fx >= 0, fy >= 0, fx < src.width, fy < src.height else { continue }
                let fBase = (fy * src.width + fx) * bpp
                let dBase = (y * dest.width + x) * bpp
                if sixteen {
                    let fa = Self.getLE16(floatBytes, fBase + 6) / 65535
                    let inv = 1 - fa
                    for c in 0..<4 {
                        let over = Self.getLE16(floatBytes, fBase + c * 2) + Self.getLE16(dst, dBase + c * 2) * inv
                        Self.putLE16(&dst, dBase + c * 2, over)
                    }
                } else {
                    let fa = Float(floatBytes[fBase + 3]) / 255
                    let inv = 1 - fa
                    for c in 0..<4 {
                        let over = Float(floatBytes[fBase + c]) + Float(dst[dBase + c]) * inv
                        dst[dBase + c] = UInt8(min(255, over.rounded()))
                    }
                }
            }
        }
        store.write(dest, bytes: dst)
    }

    static func getLE16(_ a: [UInt8], _ o: Int) -> Float {
        Float(UInt16(a[o]) | (UInt16(a[o + 1]) << 8))
    }
    static func putLE16(_ a: inout [UInt8], _ o: Int, _ v: Float) {
        let u = UInt16(max(0, min(65535, v.rounded())))
        a[o] = UInt8(u & 0xff); a[o + 1] = UInt8(u >> 8)
    }

    private func translateMask(_ maskStore: SelectionStore, canvas: Canvas, dx: Int, dy: Int) -> MaskSnapshot {
        let W = canvas.width, H = canvas.height
        let old = maskStore.readAll()
        var new = [UInt8](repeating: 0, count: W * H)
        for y in 0..<H {
            let ny = y + dy
            guard ny >= 0, ny < H else { continue }
            for x in 0..<W {
                let v = old[y * W + x]
                guard v != 0 else { continue }
                let nx = x + dx
                guard nx >= 0, nx < W else { continue }
                new[ny * W + nx] = v
            }
        }
        maskStore.clear()
        maskStore.write(PixelRect(x: 0, y: 0, width: W, height: H), bytes: new)

        let (bounds, active) = Self.boundsOfNonZero(new, width: W, height: H)
        let oldState = canvas.pixelSelection
        let shiftedPath = oldState.path.map { sub in sub.map { $0 + SIMD2<Float>(Float(dx), Float(dy)) } }
        let state: SelectionState = active
            ? SelectionState(isActive: true, bounds: bounds, version: oldState.version + 1, path: shiftedPath)
            : .none
        updateActiveSelectionState(state)
        return MaskSnapshot(state: state,
                            tiles: active ? MaskSnapshot.nonEmptyTiles(maskStore, tileSize: config.tileSize, within: bounds) : [])
    }

    private func boundingRect(_ a: PixelRect, _ b: PixelRect) -> PixelRect {
        let x0 = min(a.x, b.x), y0 = min(a.y, b.y)
        let x1 = max(a.x + a.width, b.x + b.width), y1 = max(a.y + a.height, b.y + b.height)
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func clampRect(_ r: PixelRect, _ W: Int, _ H: Int) -> PixelRect {
        let x0 = max(0, r.x), y0 = max(0, r.y)
        let x1 = min(W, r.x + r.width), y1 = min(H, r.y + r.height)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}
