//
//  BrushTip.swift
//  Haze — model
//

import Foundation

struct BrushTip: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let builtIn: Bool

    init(id: UUID, name: String, builtIn: Bool = true) {
        self.id = id
        self.name = name
        self.builtIn = builtIn
    }
}

enum BrushTipCatalog {
    static let resolution = 128

    static let chalkID      = UUID(uuidString: "0A000001-0000-0000-0000-000000000003")!
    static let spatterID    = UUID(uuidString: "0A000001-0000-0000-0000-000000000004")!
    static let squareID     = UUID(uuidString: "0A000001-0000-0000-0000-000000000005")!

    static let builtIns: [BrushTip] = [
        BrushTip(id: chalkID,     name: "Chalk"),
        BrushTip(id: spatterID,   name: "Spatter"),
        BrushTip(id: squareID,    name: "Square"),
    ]

    static func tip(_ id: UUID?) -> BrushTip? {
        guard let id else { return nil }
        return builtIns.first { $0.id == id }
    }

    static func coverage(for id: UUID) -> (bytes: [UInt8], width: Int)? {
        let w = resolution
        var out = [UInt8](repeating: 0, count: w * w)
        switch id {
        case chalkID:
            fill(&out, w) { r, nx, ny in
                let base = 1 - smooth(0.80, 1.0, r)
                let n = fbm(nx * 3.1 + 11, ny * 3.1 - 7)
                return base * (0.30 + 0.70 * n)
            }
        case squareID:
            fill(&out, w) { _, nx, ny in
                let e = max(abs(nx), abs(ny))
                return 1 - smooth(0.88, 1.0, e)
            }
        case spatterID:
            spatter(&out, w)
        default:
            return nil
        }
        return (out, w)
    }

    // MARK: - Generation helpers (pure, deterministic)

    static let tipContentFrac: Float = 0.85

    private static func fill(_ out: inout [UInt8], _ w: Int, _ f: (_ r: Float, _ nx: Float, _ ny: Float) -> Float) {
        let s = 1 / tipContentFrac
        for y in 0..<w {
            let ny = ((Float(y) + 0.5) / Float(w) * 2 - 1) * s
            for x in 0..<w {
                let nx = ((Float(x) + 0.5) / Float(w) * 2 - 1) * s
                let r = (nx * nx + ny * ny).squareRoot()
                let c = max(0, min(1, f(r, nx, ny)))
                out[y * w + x] = UInt8((c * 255).rounded())
            }
        }
    }

    private static func spatter(_ out: inout [UInt8], _ w: Int) {
        var cov = [Float](repeating: 0, count: w * w)
        var rng = SplitMix64(seed: 0x5EED_5A11)
        let dots = 260
        for _ in 0..<dots {
            var cx: Float = 0, cy: Float = 0
            repeat { cx = rng.unitBipolar(); cy = rng.unitBipolar() } while cx * cx + cy * cy > 0.9
            var rad = 0.03 + 0.06 * rng.unit()
            let peak = 0.5 + 0.5 * rng.unit()
            cx *= tipContentFrac; cy *= tipContentFrac; rad *= tipContentFrac
            let x0 = max(0, Int((cx - rad + 1) / 2 * Float(w)))
            let x1 = min(w - 1, Int((cx + rad + 1) / 2 * Float(w)))
            let y0 = max(0, Int((cy - rad + 1) / 2 * Float(w)))
            let y1 = min(w - 1, Int((cy + rad + 1) / 2 * Float(w)))
            guard x1 >= x0, y1 >= y0 else { continue }
            for y in y0...y1 {
                let ny = (Float(y) + 0.5) / Float(w) * 2 - 1
                for x in x0...x1 {
                    let nx = (Float(x) + 0.5) / Float(w) * 2 - 1
                    let d = ((nx - cx) * (nx - cx) + (ny - cy) * (ny - cy)).squareRoot() / rad
                    let a = peak * (1 - smooth(0.2, 1.0, d))
                    if a > cov[y * w + x] { cov[y * w + x] = a }
                }
            }
        }
        for i in 0..<cov.count { out[i] = UInt8((max(0, min(1, cov[i])) * 255).rounded()) }
    }

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    private static func hash(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }
    private static func valueNoise(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - floor(x), yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi), b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }
    private static func fbm(_ x: Float, _ y: Float) -> Float {
        var f: Float = 0, amp: Float = 0.6, freq: Float = 1
        for _ in 0..<3 { f += amp * valueNoise(x * freq, y * freq); freq *= 2.03; amp *= 0.5 }
        return max(0, min(1, f))
    }
}
