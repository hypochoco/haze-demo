//
//  Store+Gradient.swift
//  Haze — commands
//

import simd

extension Store {

    var canApplyGradient: Bool {
        hasCanvas && selection.count <= 1 && activeCanvas?.selectedLayerID != nil
    }

    func applyGradient(from start: SIMD2<Float>, to end: SIMD2<Float>) {
        guard hasCanvas else { return }
        guard selection.count <= 1 else { notices.post("Select a single layer for the gradient", .error); return }
        guard let canvas = activeCanvas, let id = canvas.selectedLayerID,
              let store = render.resources.store(for: .layer(id), canvas: canvas) else {
            notices.post("Select a layer for the gradient", .warning); return
        }
        let dx = end.x - start.x, dy = end.y - start.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0.0001 else { return }
        let len = len2.squareRoot()

        let active = canvas.pixelSelection.isActive
        let bounds = active ? canvas.pixelSelection.bounds
                            : PixelRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        guard !bounds.isEmpty else { return }
        let maskBytes: [UInt8]? = active ? render.resources.selection(for: canvas)?.read(bounds) : nil
        if active && maskBytes == nil { return }

        let depth = canvas.colorMode.depth
        let g = editor.gradient
        let ramp = g.effectiveStops(foreground: foregroundColor)

        func u8(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }

        let pe = PixelEditRecorder.capture(target: .layer(id), rect: bounds, canvas: canvas,
                                           render: render, tileSize: config.tileSize, title: "Gradient") {
            guard var out = store.read(bounds) else { return }
            for row in 0..<bounds.height {
                let py = Float(bounds.y + row) + 0.5
                for col in 0..<bounds.width {
                    let px = Float(bounds.x + col) + 0.5
                    var t: Float
                    switch g.type {
                    case .linear: t = ((px - start.x) * dx + (py - start.y) * dy) / len2
                    case .radial:
                        let ex = px - start.x, ey = py - start.y
                        t = (ex * ex + ey * ey).squareRoot() / len
                    }
                    t = min(1, max(0, t))
                    if g.reverse { t = 1 - t }

                    let c = GradientSettings.sample(ramp, at: t)
                    let i = row * bounds.width + col
                    let cov = maskBytes.map { Float($0[i]) / 255 } ?? 1
                    let sA = max(0, min(1, c.w)) * cov
                    if sA <= 0 { continue }
                    let invA = 1 - sA
                    let cr = max(0, min(1, c.x)), cg = max(0, min(1, c.y)), cb = max(0, min(1, c.z))
                    if depth == .eight {
                        let o = i * 4
                        out[o + 0] = u8(cb * sA * 255 + Float(out[o + 0]) * invA)
                        out[o + 1] = u8(cg * sA * 255 + Float(out[o + 1]) * invA)
                        out[o + 2] = u8(cr * sA * 255 + Float(out[o + 2]) * invA)
                        out[o + 3] = u8(sA * 255 + Float(out[o + 3]) * invA)
                    } else {
                        let o = i * 8
                        Self.putLE16(&out, o + 0, cr * sA * 65535 + Self.getLE16(out, o + 0) * invA)
                        Self.putLE16(&out, o + 2, cg * sA * 65535 + Self.getLE16(out, o + 2) * invA)
                        Self.putLE16(&out, o + 4, cb * sA * 65535 + Self.getLE16(out, o + 4) * invA)
                        Self.putLE16(&out, o + 6, sA * 65535 + Self.getLE16(out, o + 6) * invA)
                    }
                }
            }
            store.write(bounds, bytes: out)
        }
        if let pe { record(pe) }
    }
}
