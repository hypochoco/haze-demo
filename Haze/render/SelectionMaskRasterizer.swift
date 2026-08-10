//
//  SelectionMaskRasterizer.swift
//  Haze — render
//

import simd

enum SelectionMaskRasterizer {

    static func rasterize(_ subpaths: [[SIMD2<Float>]], width: Int, height: Int,
                          samplesY: Int = 4) -> (bounds: PixelRect, coverage: [UInt8])? {
        var edges: [(a: SIMD2<Float>, b: SIMD2<Float>)] = []
        var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for path in subpaths where path.count >= 3 {
            for i in 0..<path.count {
                let a = path[i], b = path[(i + 1) % path.count]
                edges.append((a, b))
                minX = min(minX, a.x); minY = min(minY, a.y)
                maxX = max(maxX, a.x); maxY = max(maxY, a.y)
            }
        }
        guard !edges.isEmpty,
              let bounds = PixelRect.fromBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                                                canvasWidth: width, canvasHeight: height)
        else { return nil }

        let w = bounds.width, h = bounds.height
        let s = max(1, samplesY)
        let subWeight = 1.0 / Float(s)
        var coverage = [UInt8](repeating: 0, count: w * h)
        var row = [Float](repeating: 0, count: w)
        var xs = [Float]()

        for py in 0..<h {
            for k in 0..<w { row[k] = 0 }
            for sy in 0..<s {
                let yw = Float(bounds.y + py) + (Float(sy) + 0.5) / Float(s)
                xs.removeAll(keepingCapacity: true)
                for e in edges {
                    let y0 = e.a.y, y1 = e.b.y
                    if (y0 <= yw && y1 > yw) || (y1 <= yw && y0 > yw) {
                        let t = (yw - y0) / (y1 - y0)
                        xs.append(e.a.x + t * (e.b.x - e.a.x))
                    }
                }
                guard xs.count >= 2 else { continue }
                xs.sort()
                var i = 0
                while i + 1 < xs.count {
                    addSpan(&row, xa: xs[i], xb: xs[i + 1], boundsX: bounds.x, w: w, weight: subWeight)
                    i += 2
                }
            }
            let base = py * w
            for k in 0..<w {
                coverage[base + k] = UInt8(max(0, min(255, (row[k] * 255).rounded())))
            }
        }
        return (bounds, coverage)
    }

    private static func addSpan(_ row: inout [Float], xa: Float, xb: Float,
                                boundsX: Int, w: Int, weight: Float) {
        let lo = min(xa, xb) - Float(boundsX)
        let hi = max(xa, xb) - Float(boundsX)
        guard hi > 0, lo < Float(w) else { return }
        let c0 = max(0, Int(lo.rounded(.down)))
        let c1 = min(w - 1, Int(hi.rounded(.up)) - 1)
        guard c0 <= c1 else { return }
        for c in c0...c1 {
            let overlap = min(Float(c + 1), hi) - max(Float(c), lo)
            if overlap > 0 { row[c] += overlap * weight }
        }
    }
}
