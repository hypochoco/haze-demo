//
//  ColorPanelContent.swift
//  Haze — views/panels
//

import SwiftUI
import simd

struct ColorPanelContent: View {
    @ObservedObject var store: Store
    @State private var hsv = HSVColor(h: 0, s: 0, v: 0, a: 1)
    @State private var hexText = "000000"

    var body: some View {
        VStack(spacing: 8) {
            SVSquare(hue: hsv.h, sat: $hsv.s, val: $hsv.v)
                .frame(height: 120)
            HueSlider(hue: $hsv.h)
            AlphaSlider(rgb: hsv.rgba, alpha: $hsv.a)
            HStack(spacing: 8) {
                ZStack {
                    Checkerboard()
                    Color(rgba: hsv.rgba, space: store.activeCanvas?.colorMode.space ?? .sRGB)
                }
                .frame(width: 40, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.3)))
                Text("#").foregroundStyle(.secondary)
                TextField("RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .font(.callout.monospaced())
                    .onSubmit { applyHex() }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { syncFrom(store.foregroundColor) }
        .onChange(of: store.foregroundColor) { _, new in
            if !approxEqual(new, hsv.rgba) { syncFrom(new) }
        }
        .onChange(of: hsv) { _, _ in
            let rgba = hsv.rgba
            if !approxEqual(rgba, store.foregroundColor) { store.foregroundColor = rgba }
            hexText = Self.hex(rgba)
        }
    }

    private func syncFrom(_ rgba: SIMD4<Float>) {
        hsv = HSVColor(rgba: rgba, fallbackHue: hsv.h)
        hexText = Self.hex(rgba)
    }

    private func applyHex() {
        guard let rgb = Self.parseHex(hexText) else { hexText = Self.hex(hsv.rgba); return }
        hsv = HSVColor(rgba: SIMD4(rgb.0, rgb.1, rgb.2, hsv.a), fallbackHue: hsv.h)
    }

    private func approxEqual(_ a: SIMD4<Float>, _ b: SIMD4<Float>, eps: Float = 0.001) -> Bool {
        abs(a.x - b.x) < eps && abs(a.y - b.y) < eps && abs(a.z - b.z) < eps && abs(a.w - b.w) < eps
    }

    static func hex(_ c: SIMD4<Float>) -> String {
        func b(_ f: Float) -> Int { Int((min(max(f, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", b(c.x), b(c.y), b(c.z))
    }

    static func parseHex(_ s: String) -> (Float, Float, Float)? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return (Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255)
    }
}

// MARK: - Saturation / Value square

private struct SVSquare: View {
    let hue: Float
    @Binding var sat: Float
    @Binding var val: Float

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Rectangle().fill(Color(hue: Double(hue), saturation: 1, brightness: 1))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 3))
                    .frame(width: 12, height: 12)
                    .position(x: CGFloat(sat) * w, y: CGFloat(1 - val) * h)
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                sat = Float(min(max(g.location.x / w, 0), 1))
                val = Float(min(max(1 - g.location.y / h, 0), 1))
            })
        }
    }
}

// MARK: - Hue slider

private struct HueSlider: View {
    @Binding var hue: Float
    private let hues: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                LinearGradient(gradient: Gradient(colors: hues), startPoint: .leading, endPoint: .trailing)
                marker.position(x: CGFloat(hue) * w, y: geo.size.height / 2)
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                hue = Float(min(max(g.location.x / w, 0), 1))
            })
        }
        .frame(height: 14)
    }

    private var marker: some View {
        Circle().strokeBorder(.white, lineWidth: 2)
            .background(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 3))
            .frame(width: 14, height: 14)
    }
}

// MARK: - Alpha slider

private struct AlphaSlider: View {
    let rgb: SIMD4<Float>
    @Binding var alpha: Float

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let opaque = Color(rgba: SIMD4(rgb.x, rgb.y, rgb.z, 1))
            ZStack(alignment: .leading) {
                Checkerboard()
                LinearGradient(colors: [opaque.opacity(0), opaque], startPoint: .leading, endPoint: .trailing)
                Circle().strokeBorder(.white, lineWidth: 2)
                    .background(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 3))
                    .frame(width: 14, height: 14)
                    .position(x: CGFloat(alpha) * w, y: geo.size.height / 2)
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                alpha = Float(min(max(g.location.x / w, 0), 1))
            })
        }
        .frame(height: 14)
    }
}
