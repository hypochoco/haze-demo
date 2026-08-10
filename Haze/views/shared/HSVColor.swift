//
//  HSVColor.swift
//  Haze — views/shared
//

import simd

struct HSVColor: Equatable {
    var h: Float
    var s: Float
    var v: Float
    var a: Float

    init(h: Float, s: Float, v: Float, a: Float = 1) {
        self.h = h; self.s = s; self.v = v; self.a = a
    }

    init(rgba c: SIMD4<Float>, fallbackHue: Float = 0) {
        let r = c.x, g = c.y, b = c.z
        let mx = max(r, max(g, b)), mn = min(r, min(g, b)), d = mx - mn
        var hue = fallbackHue
        if d > 1e-6 {
            var h6: Float
            if mx == r      { h6 = (g - b) / d }
            else if mx == g { h6 = (b - r) / d + 2 }
            else            { h6 = (r - g) / d + 4 }
            hue = h6 / 6
            hue -= floor(hue)
        }
        self.h = hue
        self.s = mx <= 1e-6 ? 0 : d / mx
        self.v = mx
        self.a = c.w
    }

    var rgba: SIMD4<Float> {
        guard s > 1e-6 else { return SIMD4(v, v, v, a) }
        let hh = (h - floor(h)) * 6
        let i = Int(hh) % 6
        let f = hh - Float(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let rgb: (Float, Float, Float)
        switch i {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        return SIMD4(rgb.0, rgb.1, rgb.2, a)
    }
}
