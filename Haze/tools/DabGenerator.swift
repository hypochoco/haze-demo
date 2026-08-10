//
//  DabGenerator.swift
//  Haze — tools
//

import simd

struct Dab: Equatable {
    var center: SIMD2<Float>
    var radius: Float
    var flow: Float = 1
    var opacity: Float = 1
    var angle: Float = 0
}

struct DabGenerator {
    let baseRadius: Float
    let spacing: Float
    let baseFlow: Float
    let pressureSize: Float
    let pressureFlow: Float
    let pressureOpacity: Float

    let angleBase: Float
    let angleJitter: Float
    let sizeJitter: Float
    let scatter: Float
    let angleFollowsDirection: Bool
    private let hasDynamics: Bool

    private var last: SIMD2<Float>?
    private var lastPressure: Float = 1
    private var carry: Float = 0
    private var rng: SplitMix64

    init(radius: Float, spacing: Float, flow: Float = 1,
         pressureSize: Float = 0, pressureFlow: Float = 0, pressureOpacity: Float = 0,
         angle: Float = 0, angleJitter: Float = 0, sizeJitter: Float = 0, scatter: Float = 0,
         angleFollowsDirection: Bool = false) {
        self.baseRadius = max(0.5, radius)
        self.spacing = max(1, spacing)
        self.baseFlow = max(0, min(1, flow))
        self.pressureSize = pressureSize
        self.pressureFlow = pressureFlow
        self.pressureOpacity = pressureOpacity
        self.angleBase = angle
        self.angleJitter = max(0, min(1, angleJitter))
        self.sizeJitter = max(0, min(1, sizeJitter))
        self.scatter = max(0, scatter)
        self.angleFollowsDirection = angleFollowsDirection
        self.hasDynamics = angle != 0 || angleJitter > 0 || sizeJitter > 0 || scatter > 0 || angleFollowsDirection
        self.rng = SplitMix64(seed: 0xB405)
    }

    mutating func begin(_ p: SIMD2<Float>, pressure: Float = 1) -> [Dab] {
        last = p
        lastPressure = pressure
        carry = 0
        rng = SplitMix64(seed: (UInt64(p.x.bitPattern) << 32) ^ UInt64(p.y.bitPattern) ^ 0x9E37_79B9)
        return [makeDab(p, pressure, dir: .zero)]
    }

    mutating func extend(to p: SIMD2<Float>, pressure: Float = 1) -> [Dab] {
        guard let a = last else { return begin(p, pressure: pressure) }
        let p0 = lastPressure
        defer { last = p; lastPressure = pressure }
        let delta = p - a
        let len = simd_length(delta)
        guard len > 0 else { return [] }
        let dir = delta / len
        var dabs: [Dab] = []
        var next = spacing - carry
        while next <= len {
            let t = next / len
            dabs.append(makeDab(a + dir * next, p0 + (pressure - p0) * t, dir: dir))
            next += spacing
        }
        carry = dabs.isEmpty ? carry + len : len - (next - spacing)
        return dabs
    }

    private mutating func makeDab(_ center: SIMD2<Float>, _ pressure: Float, dir: SIMD2<Float>) -> Dab {
        var radius = max(0.5, baseRadius * (1 + pressureSize * (pressure - 1)))
        let flow = max(0, min(1, baseFlow * (1 + pressureFlow * (pressure - 1))))
        let opacity = max(0, min(1, 1 + pressureOpacity * (pressure - 1)))
        guard hasDynamics else { return Dab(center: center, radius: radius, flow: flow, opacity: opacity) }

        var c = center
        if sizeJitter > 0 { radius = max(0.5, radius * (1 + sizeJitter * rng.unitBipolar())) }
        if scatter > 0 {
            let perp = simd_length(dir) > 0 ? SIMD2<Float>(-dir.y, dir.x) : SIMD2<Float>(1, 0)
            c += perp * (scatter * baseRadius * 2 * rng.unitBipolar())
        }
        var angle = angleBase
        if angleFollowsDirection, simd_length(dir) > 0 { angle += atan2(dir.y, dir.x) }
        if angleJitter > 0 { angle += angleJitter * .pi * rng.unitBipolar() }
        return Dab(center: c, radius: radius, flow: flow, opacity: opacity, angle: angle)
    }
}
