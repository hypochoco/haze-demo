//
//  Camera.swift
//  Haze — render
//

import simd

struct Camera {
    var zoom: Float = 1
    var centerCanvas: SIMD2<Float> = .zero

    static let minZoom: Float = 0.02
    static let maxZoom: Float = 64

    static func fitted(canvasWidth w: Int, canvasHeight h: Int, viewPoints vp: SIMD2<Float>) -> Camera {
        guard w > 0, h > 0, vp.x > 0, vp.y > 0 else { return Camera() }
        let z = min(vp.x / Float(w), vp.y / Float(h)) * 0.95
        return Camera(zoom: z, centerCanvas: [Float(w) / 2, Float(h) / 2])
    }

    func clampedZoom(_ z: Float) -> Float { min(max(z, Self.minZoom), Self.maxZoom) }

    mutating func clampCenter(canvasWidth w: Int, canvasHeight h: Int,
                              viewPoints vp: SIMD2<Float>, keep: Float = 0.25) {
        guard w > 0, h > 0, vp.x > 0, vp.y > 0, zoom > 0 else { return }
        centerCanvas.x = Self.clampAxis(centerCanvas.x, canvasExtent: Float(w), halfView: (vp.x / 2) / zoom, keep: keep)
        centerCanvas.y = Self.clampAxis(centerCanvas.y, canvasExtent: Float(h), halfView: (vp.y / 2) / zoom, keep: keep)
    }

    private static func clampAxis(_ c: Float, canvasExtent wc: Float, halfView hv: Float, keep: Float) -> Float {
        let overlap = keep * min(wc, 2 * hv)
        let lo = overlap - hv
        let hi = wc + hv - overlap
        return min(max(c, lo), hi)
    }

    // MARK: - View(points, top-left) ↔ canvas mapping

    func canvasPoint(_ viewPt: SIMD2<Float>, viewPoints vp: SIMD2<Float>) -> SIMD2<Float> {
        (viewPt - vp / 2) / zoom + centerCanvas
    }

    func viewPoint(_ canvas: SIMD2<Float>, viewPoints vp: SIMD2<Float>) -> SIMD2<Float> {
        (canvas - centerCanvas) * zoom + vp / 2
    }

    // MARK: - Present transform

    func matrix(canvasWidth w: Int, canvasHeight h: Int,
                viewport vp: SIMD2<Float>, backingScale s: Float) -> simd_float4x4 {
        let vw = max(vp.x, 1), vh = max(vp.y, 1)
        let z = zoom * s
        let sx = Float(w) * z * 2 / vw
        let sy = Float(h) * z * 2 / vh
        let offX = Float(w) / 2 - centerCanvas.x
        let offY = Float(h) / 2 - centerCanvas.y
        var m = matrix_identity_float4x4
        m.columns.0.x = sx
        m.columns.1.y = sy
        m.columns.3.x = offX * z * 2 / vw
        m.columns.3.y = -offY * z * 2 / vh
        return m
    }
}
