//
//  RotationDial.swift
//  Haze — views/panels
//

import SwiftUI

struct RotationDial: View {
    @Binding var angleDegrees: Float

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let rInner = side / 2 - 3
            let rad = CGFloat(angleDegrees) * .pi / 180
            let handle = CGPoint(x: c.x + cos(rad) * rInner, y: c.y + sin(rad) * rInner)
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08))
                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                Path { p in p.move(to: c); p.addLine(to: handle) }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(Color.accentColor).frame(width: 9, height: 9).position(handle)
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 3, height: 3).position(c)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let dx = v.location.x - c.x, dy = v.location.y - c.y
                        guard dx != 0 || dy != 0 else { return }
                        var deg = Float(atan2(dy, dx) * 180 / .pi)
                        if deg < 0 { deg += 360 }
                        angleDegrees = deg
                    }
            )
            .accessibilityLabel("Brush tip rotation")
            .accessibilityValue("\(Int(angleDegrees)) degrees")
        }
    }
}
