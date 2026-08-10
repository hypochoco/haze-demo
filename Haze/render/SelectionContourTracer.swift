//
//  SelectionContourTracer.swift
//  Haze — render
//

import simd

enum SelectionContourTracer {

    static func trace(mask: [UInt8], width: Int, height: Int, threshold: UInt8 = 128) -> [[SIMD2<Float>]] {
        guard width > 0, height > 0, mask.count == width * height else { return [] }

        @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] >= threshold
        }

        let stride = width + 1
        @inline(__always) func vid(_ vx: Int, _ vy: Int) -> Int { vx + stride * vy }

        var edgesFrom: [Int: [Int]] = [:]
        var starts: [Int] = []
        @inline(__always) func addEdge(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) {
            let a = vid(ax, ay)
            if edgesFrom[a] == nil { edgesFrom[a] = []; starts.append(a) }
            edgesFrom[a]!.append(vid(bx, by))
        }

        for y in 0..<height {
            for x in 0..<width where inside(x, y) {
                if !inside(x, y - 1) { addEdge(x,     y,     x + 1, y)     }
                if !inside(x + 1, y) { addEdge(x + 1, y,     x + 1, y + 1) }
                if !inside(x, y + 1) { addEdge(x + 1, y + 1, x,     y + 1) }
                if !inside(x - 1, y) { addEdge(x,     y + 1, x,     y)     }
            }
        }
        if edgesFrom.isEmpty { return [] }

        @inline(__always) func coord(_ id: Int) -> (Int, Int) { (id % stride, id / stride) }

        var loops: [[SIMD2<Float>]] = []
        for s in starts {
            while let outs = edgesFrom[s], !outs.isEmpty {
                var loopIDs: [Int] = [s]
                var current = s
                var next = edgesFrom[current]!.removeLast()
                while next != s {
                    loopIDs.append(next)
                    guard var nexts = edgesFrom[next], !nexts.isEmpty else { break }
                    let following = nexts.removeLast()
                    edgesFrom[next] = nexts
                    current = next
                    next = following
                }
                loops.append(simplify(loopIDs.map { let (x, y) = coord($0); return SIMD2<Float>(Float(x), Float(y)) }))
            }
        }
        return loops.filter { $0.count >= 3 }
    }

    private static func simplify(_ pts: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard pts.count >= 3 else { return pts }
        var out: [SIMD2<Float>] = []
        let n = pts.count
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            let d1 = cur - prev, d2 = next - cur
            if d1.x * d2.y - d1.y * d2.x != 0 { out.append(cur) }
        }
        return out.count >= 3 ? out : pts
    }
}
