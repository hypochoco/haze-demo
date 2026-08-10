//
//  Color+RGBA.swift
//  Haze — views/shared
//

import SwiftUI
import AppKit
import simd

extension Color {
    init(rgba: SIMD4<Float>) {
        self.init(.sRGB, red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), opacity: Double(rgba.w))
    }

    init(rgba: SIMD4<Float>, space: WorkingSpace) {
        let cs: Color.RGBColorSpace = space == .displayP3 ? .displayP3 : .sRGB
        self.init(cs, red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), opacity: Double(rgba.w))
    }

    var rgbaFloats: SIMD4<Float> {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return SIMD4<Float>(Float(ns.redComponent), Float(ns.greenComponent),
                            Float(ns.blueComponent), Float(ns.alphaComponent))
    }
}
