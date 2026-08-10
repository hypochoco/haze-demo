//
//  PixelConversion.swift
//  Haze — io
//

import Foundation

enum PixelConversion {

    static func premultipliedBGRAToStraightRGBA(_ src: [UInt8]) -> [UInt8] {
        let count = src.count / 4
        var out = [UInt8](repeating: 0, count: src.count)
        for i in 0..<count {
            let o = i * 4
            let b = src[o + 0], g = src[o + 1], r = src[o + 2], a = src[o + 3]
            if a == 0 {
                out[o + 0] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 0
            } else if a == 255 {
                out[o + 0] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = 255
            } else {
                let af = Float(a)
                out[o + 0] = unpremul(r, af)
                out[o + 1] = unpremul(g, af)
                out[o + 2] = unpremul(b, af)
                out[o + 3] = a
            }
        }
        return out
    }

    static func straightRGBAToPremultipliedBGRA(_ src: [UInt8]) -> [UInt8] {
        let count = src.count / 4
        var out = [UInt8](repeating: 0, count: src.count)
        for i in 0..<count {
            let o = i * 4
            let r = src[o + 0], g = src[o + 1], b = src[o + 2], a = src[o + 3]
            if a == 255 {
                out[o + 0] = b; out[o + 1] = g; out[o + 2] = r; out[o + 3] = 255
            } else if a == 0 {
                out[o + 0] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 0
            } else {
                out[o + 0] = premul(b, a)
                out[o + 1] = premul(g, a)
                out[o + 2] = premul(r, a)
                out[o + 3] = a
            }
        }
        return out
    }

    private static func unpremul(_ c: UInt8, _ a255: Float) -> UInt8 {
        UInt8(max(0, min(255, (Float(c) * 255 / a255).rounded())))
    }
    private static func premul(_ c: UInt8, _ a: UInt8) -> UInt8 {
        UInt8(max(0, min(255, (Float(c) * Float(a) / 255).rounded())))
    }

    // MARK: - Import coercion (STRAIGHT/codec RGBA) → the demo's fixed 8-bit sRGB

    static func straightRGBA16ToStraightRGBA8(_ src: [UInt8]) -> [UInt8] {
        let count = src.count / 8
        var out = [UInt8](repeating: 0, count: count * 4)
        src.withUnsafeBytes { (s: UnsafeRawBufferPointer) in
            let sp = s.bindMemory(to: UInt16.self)
            for i in 0..<count {
                let si = i * 4, o = i * 4
                for k in 0..<4 { out[o + k] = narrow(UInt16(littleEndian: sp[si + k])) }
            }
        }
        return out
    }

    private static func narrow(_ v: UInt16) -> UInt8 {
        UInt8(max(0, min(255, (Float(v) / 257).rounded())))
    }

    static func remapStraightRGBA8(_ src: [UInt8], from: WorkingSpace, to: WorkingSpace) -> [UInt8] {
        guard from != to else { return src }
        let m = (from == .sRGB && to == .displayP3) ? s2p : p2s
        var out = src
        let count = src.count / 4
        for i in 0..<count {
            let o = i * 4
            let r = srgbToLinear(Float(src[o + 0]) / 255)
            let g = srgbToLinear(Float(src[o + 1]) / 255)
            let b = srgbToLinear(Float(src[o + 2]) / 255)
            out[o + 0] = u8(linearToSrgb(clamp01(m[0]*r + m[1]*g + m[2]*b)))
            out[o + 1] = u8(linearToSrgb(clamp01(m[3]*r + m[4]*g + m[5]*b)))
            out[o + 2] = u8(linearToSrgb(clamp01(m[6]*r + m[7]*g + m[8]*b)))
        }
        return out
    }

    private static let s2p: [Float] = [0.822462, 0.177538, 0.000000,
                                       0.033194, 0.966806, 0.000000,
                                       0.017083, 0.072397, 0.910520]
    private static let p2s: [Float] = [1.224940, -0.224940,  0.000000,
                                       -0.042057, 1.042057,  0.000000,
                                       -0.019638, -0.078636, 1.098273]

    private static func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }
    private static func srgbToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }
    private static func linearToSrgb(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
    }
    private static func u8(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
}
