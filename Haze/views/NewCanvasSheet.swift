//
//  NewCanvasSheet.swift
//  Haze — views
//

import SwiftUI

struct NewCanvasSheet: View {
    @ObservedObject var store: Store
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var width = 1024
    @State private var height = 1024
    @State private var background: CanvasBackground = .white
    @State private var dpi: Int

    init(store: Store, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        _dpi = State(initialValue: store.config.newCanvasDPI)
    }

    private let presets: [(name: String, w: Int, h: Int)] = [
        ("1024²", 1024, 1024), ("2048²", 2048, 2048),
        ("1920×1080", 1920, 1080), ("3840×2160", 3840, 2160),
    ]

    private let labelW: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Canvas").font(.headline)

            HStack(spacing: 8) {
                Text("Name").frame(width: labelW, alignment: .trailing)
                TextField("Canvas \(store.document.canvases.count + 1)", text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 190)
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.name) { p in
                    Button(p.name) { width = p.w; height = p.h }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Text("Width").frame(width: labelW, alignment: .trailing)
                TextField("", value: $width, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                Text("px").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Height").frame(width: labelW, alignment: .trailing)
                TextField("", value: $height, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                Text("px").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Background").frame(width: labelW, alignment: .trailing)
                Picker("", selection: $background) {
                    ForEach(CanvasBackground.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }

            HStack(spacing: 8) {
                Text("Resolution").frame(width: labelW, alignment: .trailing)
                TextField("", value: $dpi, format: .number).frame(width: 70).textFieldStyle(.roundedBorder)
                Stepper("", value: $dpi, in: 1...2400).labelsHidden()
                Text("DPI").foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func create() {
        isPresented = false
        guard CanvasCloseCommand.makeRoomForNewCanvas(store: store) else { return }
        store.newCanvas(width: max(1, width), height: max(1, height),
                        name: name, background: background,
                        dpi: Double(max(1, dpi)))
    }
}
