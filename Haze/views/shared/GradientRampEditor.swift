//
//  GradientRampEditor.swift
//  Haze — views/shared
//

import SwiftUI
import simd

struct GradientRampEditor: View {
    @Binding var stops: [GradientStop]
    var space: WorkingSpace = .sRGB
    var foreground: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)

    @State private var selectedID: UUID?
    @State private var dragOriginPos: Float?

    private let barHeight: CGFloat = 26
    private let handleSize: CGFloat = 14

    private var sorted: [GradientStop] { stops.sorted { $0.position < $1.position } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 4) {
                    bar(w)
                    handleStrip(w)
                }
            }
            .frame(height: barHeight + 4 + handleSize)

            selectedEditor
        }
        .onAppear {
            if stops.isEmpty {
                stops = [GradientStop(position: 0, color: SIMD4<Float>(foreground.x, foreground.y, foreground.z, 1)),
                         GradientStop(position: 1, color: SIMD4<Float>(foreground.x, foreground.y, foreground.z, 0))]
            }
            if selectedID == nil { selectedID = sorted.first?.id }
        }
    }

    private func bar(_ w: CGFloat) -> some View {
        ZStack {
            Checkerboard(square: 6)
            LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
        }
        .frame(height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.4)))
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 0).onEnded { v in
            addStop(at: Float(v.location.x / max(1, w)))
        })
    }

    private var gradientStops: [Gradient.Stop] {
        let s = sorted
        guard !s.isEmpty else { return [.init(color: .clear, location: 0), .init(color: .clear, location: 1)] }
        return s.map { .init(color: Color(rgba: $0.color, space: space), location: Double(min(1, max(0, $0.position)))) }
    }

    private func handleStrip(_ w: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(maxWidth: .infinity).frame(height: handleSize)
            ForEach(stops) { stop in handle(stop, w) }
        }
        .frame(height: handleSize)
    }

    private func handle(_ stop: GradientStop, _ w: CGFloat) -> some View {
        let selected = stop.id == selectedID
        let x = CGFloat(min(1, max(0, stop.position))) * w
        return ZStack {
            Checkerboard(square: 4)
            Color(rgba: stop.color, space: space)
        }
        .frame(width: handleSize, height: handleSize)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.6),
                          lineWidth: selected ? 2 : 1))
        .offset(x: x - handleSize / 2)
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragOriginPos == nil { dragOriginPos = stop.position; selectedID = stop.id }
                if let i = stops.firstIndex(where: { $0.id == stop.id }), let o = dragOriginPos {
                    stops[i].position = min(1, max(0, o + Float(v.translation.width / max(1, w))))
                }
            }
            .onEnded { _ in dragOriginPos = nil })
    }

    @ViewBuilder private var selectedEditor: some View {
        HStack(spacing: 8) {
            Button { addInLargestGap() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("Add a colour stop")

            if let i = stops.firstIndex(where: { $0.id == selectedID }) {
                ColorPicker("", selection: colorBinding(i), supportsOpacity: true)
                    .labelsHidden().frame(width: 44)
                Slider(value: positionBinding(i), in: 0...1)
                Text("\(Int((stops[i].position * 100).rounded()))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                Button { removeSelected() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Remove stop")
                    .disabled(stops.count <= 2)
            } else {
                Text("Click the bar or + to add a stop.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    private func addStop(at t: Float) {
        let tt = min(1, max(0, t))
        let color = GradientSettings.sample(sorted, at: tt)
        let stop = GradientStop(position: tt, color: color)
        stops.append(stop)
        selectedID = stop.id
    }

    private func addInLargestGap() {
        let s = sorted
        guard s.count >= 2 else { addStop(at: s.first.map { $0.position < 0.5 ? 1 : 0 } ?? 0.5); return }
        var bestMid: Float = 0.5, best: Float = -1
        for i in 1..<s.count {
            let gap = s[i].position - s[i - 1].position
            if gap > best { best = gap; bestMid = (s[i].position + s[i - 1].position) / 2 }
        }
        addStop(at: bestMid)
    }

    private func removeSelected() {
        guard stops.count > 2, let i = stops.firstIndex(where: { $0.id == selectedID }) else { return }
        stops.remove(at: i)
        selectedID = sorted.first?.id
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { Color(rgba: stops[i].color, space: space) },
                set: { stops[i].color = $0.rgbaFloats })
    }
    private func positionBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { Double(stops[i].position) },
                set: { stops[i].position = min(1, max(0, Float($0))) })
    }
}
