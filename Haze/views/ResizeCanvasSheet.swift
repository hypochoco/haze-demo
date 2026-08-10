//
//  ResizeCanvasSheet.swift
//  Haze — views
//

import SwiftUI

struct ResizeCanvasSheet: View {
    @ObservedObject var store: Store
    @Binding var isPresented: Bool

    @State private var width: Int
    @State private var height: Int
    @State private var anchor: ResizeAnchor = .center
    @State private var resample = false

    init(store: Store, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        _width = State(initialValue: store.activeCanvas?.width ?? 1024)
        _height = State(initialValue: store.activeCanvas?.height ?? 1024)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resize Canvas").font(.headline)

            HStack(spacing: 8) {
                Text("Width").frame(width: 52, alignment: .trailing)
                TextField("", value: $width, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                Text("px").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Height").frame(width: 52, alignment: .trailing)
                TextField("", value: $height, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                Text("px").foregroundStyle(.secondary)
            }

            Picker("Method", selection: $resample) {
                Text("Crop / Extend").tag(false)
                Text("Resample").tag(true)
            }
            .pickerStyle(.radioGroup)

            if !resample {
                HStack(spacing: 8) {
                    Text("Anchor").frame(width: 52, alignment: .trailing)
                    Picker("", selection: $anchor) {
                        Text("Top-Left").tag(ResizeAnchor.topLeft)
                        Text("Center").tag(ResizeAnchor.center)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Resize") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func apply() {
        store.resizeCanvas(width: max(1, width), height: max(1, height),
                           anchor: anchor, method: resample ? .resample : .cropExtend)
        isPresented = false
    }
}
