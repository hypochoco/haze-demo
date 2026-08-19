//
//  GradientSettings.swift
//  Haze — tools
//

import Foundation
import simd

enum GradientType: String, CaseIterable, Equatable, Identifiable {
    case linear
    case radial
    var id: String { rawValue }
    var title: String { self == .linear ? "Linear" : "Radial" }
}

struct GradientStop: Identifiable, Equatable {
    var id = UUID()
    var position: Float
    var color: SIMD4<Float>
}

struct GradientSettings: Equatable {
    var type: GradientType = .linear
    var reverse: Bool = false
    var stops: [GradientStop] = []

    func effectiveStops(foreground fg: SIMD4<Float>) -> [GradientStop] {
        guard !stops.isEmpty else {
            return [GradientStop(position: 0, color: SIMD4<Float>(fg.x, fg.y, fg.z, 1)),
                    GradientStop(position: 1, color: SIMD4<Float>(fg.x, fg.y, fg.z, 0))]
        }
        return stops.sorted { $0.position < $1.position }
    }

    static func sample(_ sorted: [GradientStop], at t: Float) -> SIMD4<Float> {
        guard let first = sorted.first else { return SIMD4<Float>(repeating: 0) }
        if t <= first.position { return first.color }
        guard let last = sorted.last, t < last.position else { return sorted.last!.color }
        for i in 1..<sorted.count {
            let a = sorted[i - 1], b = sorted[i]
            if t <= b.position {
                let span = b.position - a.position
                let f = span > 1e-6 ? (t - a.position) / span : 0
                return a.color + (b.color - a.color) * f
            }
        }
        return last.color
    }
}
