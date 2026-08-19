//
//  BrushCursorOutline.swift
//  Haze — tools
//

import Foundation
import CoreGraphics

enum BrushCursorOutline {

    static let threshold: Float = 0.5
    static let minLoopArea: CGFloat = 0.0008
    static let simplifyEpsilon: CGFloat = 0.01

    // MARK: - Round brush

    static func roundContour(segments: Int = 72) -> [[CGPoint]] {
        var pts: [CGPoint] = []
        pts.reserveCapacity(segments)
        for i in 0..<segments {
            let a = 2 * Double.pi * Double(i) / Double(segments)
            pts.append(CGPoint(x: cos(a), y: sin(a)))
        }
        return [pts]
    }

    // MARK: - Textured tip

    static func tipContours(coverage bytes: [UInt8], width w: Int) -> [[CGPoint]] {
        guard w >= 2, bytes.count >= w * w else { return [] }
        let tc = CGFloat(BrushTipCatalog.tipContentFrac)
        let t = threshold

        @inline(__always) func f(_ x: Int, _ y: Int) -> Float { Float(bytes[y * w + x]) / 255 }
        @inline(__always) func norm(_ g: CGFloat) -> CGFloat { (2 * ((g + 0.5) / CGFloat(w)) - 1) / tc }

        let stride = w + 1
        @inline(__always) func hID(_ ix: Int, _ iy: Int) -> Int { ((iy * stride + ix) << 1) }
        @inline(__always) func vID(_ ix: Int, _ iy: Int) -> Int { ((iy * stride + ix) << 1) | 1 }

        var point: [Int: CGPoint] = [:]
        var adj: [Int: [Int]] = [:]
        @inline(__always) func addSeg(_ a: Int, _ pa: CGPoint, _ b: Int, _ pb: CGPoint) {
            point[a] = pa; point[b] = pb
            adj[a, default: []].append(b)
            adj[b, default: []].append(a)
        }
        @inline(__always) func lerp(_ v0: Float, _ v1: Float) -> CGFloat { CGFloat((t - v0) / (v1 - v0)) }

        for iy in 0..<(w - 1) {
            for ix in 0..<(w - 1) {
                let tl = f(ix, iy), tr = f(ix + 1, iy), br = f(ix + 1, iy + 1), bl = f(ix, iy + 1)
                var code = 0
                if tl > t { code |= 1 }
                if tr > t { code |= 2 }
                if br > t { code |= 4 }
                if bl > t { code |= 8 }
                if code == 0 || code == 15 { continue }

                func T() -> (Int, CGPoint) { (hID(ix, iy),     CGPoint(x: CGFloat(ix) + lerp(tl, tr), y: CGFloat(iy))) }
                func B() -> (Int, CGPoint) { (hID(ix, iy + 1), CGPoint(x: CGFloat(ix) + lerp(bl, br), y: CGFloat(iy + 1))) }
                func L() -> (Int, CGPoint) { (vID(ix, iy),     CGPoint(x: CGFloat(ix), y: CGFloat(iy) + lerp(tl, bl))) }
                func R() -> (Int, CGPoint) { (vID(ix + 1, iy), CGPoint(x: CGFloat(ix + 1), y: CGFloat(iy) + lerp(tr, br))) }
                @inline(__always) func seg(_ e0: (Int, CGPoint), _ e1: (Int, CGPoint)) { addSeg(e0.0, e0.1, e1.0, e1.1) }

                switch code {
                case 1:  seg(L(), T())
                case 2:  seg(T(), R())
                case 3:  seg(L(), R())
                case 4:  seg(R(), B())
                case 5:  seg(L(), T()); seg(R(), B())
                case 6:  seg(T(), B())
                case 7:  seg(L(), B())
                case 8:  seg(L(), B())
                case 9:  seg(T(), B())
                case 10: seg(T(), R()); seg(L(), B())
                case 11: seg(R(), B())
                case 12: seg(L(), R())
                case 13: seg(T(), R())
                case 14: seg(L(), T())
                default: break
                }
            }
        }

        var visited = Set<Int>()
        var loops: [[CGPoint]] = []
        for start in adj.keys {
            if visited.contains(start) { continue }
            var loop: [CGPoint] = []
            var current = start
            var prev = -1
            while !visited.contains(current), let p = point[current] {
                visited.insert(current)
                loop.append(p)
                let neighbours = adj[current] ?? []
                var next = -1
                for n in neighbours where n != prev && !visited.contains(n) { next = n; break }
                if next == -1 { break }
                prev = current; current = next
            }
            if loop.count >= 3 { loops.append(loop) }
        }

        var out: [[CGPoint]] = []
        for loop in loops {
            let normLoop = loop.map { CGPoint(x: norm($0.x), y: norm($0.y)) }
            if abs(signedArea(normLoop)) < minLoopArea { continue }
            let simplified = simplifyClosed(normLoop, epsilon: simplifyEpsilon)
            if simplified.count >= 3 { out.append(simplified) }
        }
        return out
    }

    // MARK: - Placement

    static func place(_ contours: [[CGPoint]], radiusView: CGFloat, angle: CGFloat, roundness: CGFloat) -> [[CGPoint]] {
        let ca = cos(angle), sa = sin(angle)
        let rn = max(0.05, min(1, roundness))
        return contours.map { loop in
            loop.map { p in
                let sx = p.x, sy = p.y * rn
                return CGPoint(x: (sx * ca - sy * sa) * radiusView,
                               y: (sx * sa + sy * ca) * radiusView)
            }
        }
    }

    // MARK: - Helpers

    static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 3 else { return 0 }
        var a: CGFloat = 0
        var j = pts.count - 1
        for i in 0..<pts.count { a += (pts[j].x + pts[i].x) * (pts[j].y - pts[i].y); j = i }
        return a / 2
    }

    static func simplifyClosed(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 4 else { return pts }
        var iMax = 0, jMax = 0; var dMax: CGFloat = -1
        for i in 0..<pts.count {
            let d = hypot(pts[i].x - pts[0].x, pts[i].y - pts[0].y)
            if d > dMax { dMax = d; iMax = i }
        }
        dMax = -1
        for j in 0..<pts.count {
            let d = hypot(pts[j].x - pts[iMax].x, pts[j].y - pts[iMax].y)
            if d > dMax { dMax = d; jMax = j }
        }
        let lo = min(iMax, jMax), hi = max(iMax, jMax)
        let a = Array(pts[lo...hi])
        let b = Array(pts[hi...] + pts[...lo])
        let sa = dp(a, epsilon)
        let sb = dp(b, epsilon)
        var merged = sa
        if sb.count > 2 { merged += sb[1..<(sb.count - 1)] }
        return merged.count >= 3 ? merged : pts
    }

    private static func dp(_ pts: [CGPoint], _ epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var dMax: CGFloat = 0; var idx = 0
        let a = pts.first!, b = pts.last!
        for i in 1..<(pts.count - 1) {
            let d = perpDistance(pts[i], a, b)
            if d > dMax { dMax = d; idx = i }
        }
        if dMax > epsilon {
            let left = dp(Array(pts[0...idx]), epsilon)
            let right = dp(Array(pts[idx...]), epsilon)
            return left.dropLast() + right
        }
        return [a, b]
    }

    private static func perpDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        if len < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }
}
