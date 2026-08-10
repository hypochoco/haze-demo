//
//  Store+Transform.swift
//  Haze — commands
//

import Metal
import simd

enum Affine {
    static func translate(_ t: SIMD2<Float>) -> simd_float3x3 {
        simd_float3x3(SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(t.x, t.y, 1))
    }
    static func scale(_ s: SIMD2<Float>, about c: SIMD2<Float>) -> simd_float3x3 {
        let S = simd_float3x3(SIMD3(s.x, 0, 0), SIMD3(0, s.y, 0), SIMD3(0, 0, 1))
        return translate(c) * S * translate(-c)
    }
    static func rotate(_ radians: Float, about c: SIMD2<Float>) -> simd_float3x3 {
        let cs = cos(radians), sn = sin(radians)
        let R = simd_float3x3(SIMD3(cs, sn, 0), SIMD3(-sn, cs, 0), SIMD3(0, 0, 1))
        return translate(c) * R * translate(-c)
    }
    static func apply(_ M: simd_float3x3, _ p: SIMD2<Float>) -> SIMD2<Float> {
        let v = M * SIMD3<Float>(p.x, p.y, 1)
        return [v.x, v.y]
    }
}

struct FloatingTransform {
    let layerID: LayerID
    let sourceBounds: PixelRect
    let floatTex: MTLTexture
    let erasedBytes: [UInt8]
    let srcBeforeBytes: [UInt8]
    let maskBefore: MaskSnapshot
    var matrix: simd_float3x3
}

extension Store {

    var isTransforming: Bool { floatingTransform != nil }

    var transformMatrix: simd_float3x3? { floatingTransform?.matrix }

    var transformSourceBounds: PixelRect? { floatingTransform?.sourceBounds }

    func flipTransform(horizontal: Bool) {
        guard let f = floatingTransform else { return }
        let s = f.sourceBounds
        let cLocal = SIMD2<Float>(Float(s.x) + Float(s.width) / 2, Float(s.y) + Float(s.height) / 2)
        let cw = Affine.apply(f.matrix, cLocal)
        let flip = Affine.scale(horizontal ? [-1, 1] : [1, -1], about: cw)
        setTransformMatrix(flip * f.matrix)
    }

    func floatingTransformPreview()
        -> (tex: MTLTexture, tl: SIMD2<Float>, tr: SIMD2<Float>, bl: SIMD2<Float>, br: SIMD2<Float>)? {
        guard let f = floatingTransform else { return nil }
        let s = f.sourceBounds, M = f.matrix
        return (f.floatTex,
                Affine.apply(M, [Float(s.x), Float(s.y)]),
                Affine.apply(M, [Float(s.x + s.width), Float(s.y)]),
                Affine.apply(M, [Float(s.x), Float(s.y + s.height)]),
                Affine.apply(M, [Float(s.x + s.width), Float(s.y + s.height)]))
    }

    func beginFloatingTransform() {
        guard floatingTransform == nil else { return }
        guard let lift = liftSelection("Transform") else { return }
        floatingTransform = FloatingTransform(layerID: lift.layerID, sourceBounds: lift.sourceBounds,
                                              floatTex: lift.floatTex, erasedBytes: lift.erasedBytes,
                                              srcBeforeBytes: lift.srcBeforeBytes, maskBefore: lift.maskBefore,
                                              matrix: matrix_identity_float3x3)
        floatingVersion &+= 1
        bumpContent([lift.layerID])
    }

    func setTransformMatrix(_ m: simd_float3x3) {
        guard floatingTransform != nil else { return }
        floatingTransform?.matrix = m
        floatingVersion &+= 1
    }

    func cancelFloatingTransform() {
        guard let f = floatingTransform, let canvas = activeCanvas,
              let store = render.resources.store(for: .layer(f.layerID), canvas: canvas) else {
            floatingTransform = nil; return
        }
        store.write(f.sourceBounds, bytes: f.srcBeforeBytes)
        floatingTransform = nil
        floatingVersion &+= 1
        bumpContent([f.layerID])
    }

    func commitFloatingTransform() {
        guard let f = floatingTransform, let canvas = activeCanvas,
              let store = render.resources.store(for: .layer(f.layerID), canvas: canvas),
              let maskStore = render.resources.selection(for: canvas) else { floatingTransform = nil; return }
        floatingTransform = nil
        let W = canvas.width, H = canvas.height
        let src = f.sourceBounds
        let destBounds = tclampRect(transformedBounds(src, f.matrix), W, H)
        let union = tclampRect(tboundingRect(src, destBounds), W, H)

        store.write(src, bytes: f.srcBeforeBytes)

        let target = PixelTarget.layer(f.layerID)
        let pe = PixelEditRecorder.capture(target: target, rect: union, canvas: canvas,
                                           render: render, tileSize: config.tileSize, title: "Transform Selection") {
            store.write(src, bytes: f.erasedBytes)
            rasterizeFloat(f, into: store, canvasW: W, canvasH: H)
        }

        let maskAfter = transformMask(maskStore, canvas: canvas, matrix: f.matrix)

        floatingVersion &+= 1
        bumpContent([f.layerID])

        guard let pe else { return }
        record(TransformSelectionCommand(target: target, diff: pe.diff,
                                         maskBefore: f.maskBefore, maskAfter: maskAfter))
    }

    // MARK: - Rasterisation

    private func rasterizeFloat(_ f: FloatingTransform, into store: LayerStore, canvasW: Int, canvasH: Int) {
        let src = f.sourceBounds
        let dest = tclampRect(transformedBounds(src, f.matrix), canvasW, canvasH)
        guard !dest.isEmpty, var dst = store.read(dest) else { return }
        let floatBytes = RenderContext.readBytes(from: f.floatTex)
        let bpp = f.floatTex.pixelFormat.haze_bytesPerPixel
        let sixteen = bpp == 8
        let maxV: Float = sixteen ? 65535 : 255
        let Minv = f.matrix.inverse
        let fw = src.width, fh = src.height

        for y in 0..<dest.height {
            for x in 0..<dest.width {
                let s = Affine.apply(Minv, [Float(dest.x + x), Float(dest.y + y)])
                let tx = s.x - Float(src.x), ty = s.y - Float(src.y)
                guard tx > -1, ty > -1, tx < Float(fw), ty < Float(fh) else { continue }
                let sm = Self.sampleBilinear(floatBytes, fw, fh, bpp, sixteen, tx, ty)
                let fa = sm[3] / maxV
                guard fa > 0 else { continue }
                let inv = 1 - fa
                let dBase = (y * dest.width + x) * bpp
                if sixteen {
                    for c in 0..<4 {
                        let over = sm[c] + Store.getLE16(dst, dBase + c * 2) * inv
                        Store.putLE16(&dst, dBase + c * 2, over)
                    }
                } else {
                    for c in 0..<4 {
                        let over = sm[c] + Float(dst[dBase + c]) * inv
                        dst[dBase + c] = UInt8(min(255, over.rounded()))
                    }
                }
            }
        }
        store.write(dest, bytes: dst)
    }

    private static func sampleBilinear(_ b: [UInt8], _ w: Int, _ h: Int, _ bpp: Int, _ sixteen: Bool,
                                       _ tx: Float, _ ty: Float) -> SIMD4<Float> {
        let x0 = Int(floor(tx)), y0 = Int(floor(ty))
        let fx = tx - Float(x0), fy = ty - Float(y0)
        func texel(_ xi: Int, _ yi: Int) -> SIMD4<Float> {
            let cx = min(max(xi, 0), w - 1), cy = min(max(yi, 0), h - 1)
            let base = (cy * w + cx) * bpp
            if sixteen {
                return SIMD4(getLE16(b, base + 0), getLE16(b, base + 2), getLE16(b, base + 4), getLE16(b, base + 6))
            } else {
                return SIMD4(Float(b[base + 0]), Float(b[base + 1]), Float(b[base + 2]), Float(b[base + 3]))
            }
        }
        let top = texel(x0, y0) * (1 - fx) + texel(x0 + 1, y0) * fx
        let bot = texel(x0, y0 + 1) * (1 - fx) + texel(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bot * fy
    }

    private func transformMask(_ maskStore: SelectionStore, canvas: Canvas, matrix M: simd_float3x3) -> MaskSnapshot {
        let W = canvas.width, H = canvas.height
        let old = maskStore.readAll()
        var new = [UInt8](repeating: 0, count: W * H)
        let Minv = M.inverse
        let db = tclampRect(transformedBounds(canvas.pixelSelection.bounds, M), W, H)
        for y in db.y..<(db.y + db.height) {
            for x in db.x..<(db.x + db.width) {
                let s = Affine.apply(Minv, [Float(x), Float(y)])
                let cov = Self.sampleMaskBilinear(old, W, H, s.x, s.y)
                if cov > 0 { new[y * W + x] = cov }
            }
        }
        maskStore.clear()
        maskStore.write(PixelRect(x: 0, y: 0, width: W, height: H), bytes: new)

        let (bounds, active) = Self.boundsOfNonZero(new, width: W, height: H)
        let oldState = canvas.pixelSelection
        let newPath = oldState.path.map { sub in sub.map { Affine.apply(M, $0) } }
        let state: SelectionState = active
            ? SelectionState(isActive: true, bounds: bounds, version: oldState.version + 1, path: newPath)
            : .none
        updateActiveSelectionState(state)
        return MaskSnapshot(state: state,
                            tiles: active ? MaskSnapshot.nonEmptyTiles(maskStore, tileSize: config.tileSize, within: bounds) : [])
    }

    private static func sampleMaskBilinear(_ a: [UInt8], _ W: Int, _ H: Int, _ fx: Float, _ fy: Float) -> UInt8 {
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let tx = fx - Float(x0), ty = fy - Float(y0)
        func at(_ xi: Int, _ yi: Int) -> Float { (xi < 0 || yi < 0 || xi >= W || yi >= H) ? 0 : Float(a[yi * W + xi]) }
        let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
        let bot = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
        return UInt8(min(255, (top * (1 - ty) + bot * ty).rounded()))
    }

    // MARK: - Rect helpers (file-local)

    private func transformedBounds(_ r: PixelRect, _ M: simd_float3x3) -> PixelRect {
        let corners = [SIMD2<Float>(Float(r.x), Float(r.y)),
                       SIMD2<Float>(Float(r.x + r.width), Float(r.y)),
                       SIMD2<Float>(Float(r.x), Float(r.y + r.height)),
                       SIMD2<Float>(Float(r.x + r.width), Float(r.y + r.height))].map { Affine.apply(M, $0) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let x0 = Int(floor(xs.min()!)), y0 = Int(floor(ys.min()!))
        let x1 = Int(ceil(xs.max()!)), y1 = Int(ceil(ys.max()!))
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func tboundingRect(_ a: PixelRect, _ b: PixelRect) -> PixelRect {
        let x0 = min(a.x, b.x), y0 = min(a.y, b.y)
        let x1 = max(a.x + a.width, b.x + b.width), y1 = max(a.y + a.height, b.y + b.height)
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func tclampRect(_ r: PixelRect, _ W: Int, _ H: Int) -> PixelRect {
        let x0 = max(0, r.x), y0 = max(0, r.y)
        let x1 = min(W, r.x + r.width), y1 = min(H, r.y + r.height)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}
