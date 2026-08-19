//
//  GradientPanelContent.swift
//  Haze — views/panels
//

import SwiftUI
import simd

struct GradientPanelContent: View {
    @ObservedObject var store: Store
    @ObservedObject private var editorStore: EditorStore

    init(store: Store) {
        _store = ObservedObject(wrappedValue: store)
        _editorStore = ObservedObject(wrappedValue: store.editorStore)
    }

    var body: some View {
        Group {
            if store.activeCanvas == nil {
                VStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No canvas open").foregroundStyle(.secondary).font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Type", selection: typeBinding) {
                        ForEach(GradientType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    Toggle("Reverse", isOn: reverseBinding).font(.caption)

                    Text(store.editor.activeTool == .gradient
                         ? "Drag start → end on the canvas to fill (Foreground → Transparent)."
                         : "Select the Gradient tool (G) to draw.")
                        .font(.caption2).foregroundStyle(.tertiary)

                    Spacer()
                }
                .padding(8)
            }
        }
    }

    private var typeBinding: Binding<GradientType> {
        Binding(get: { store.editor.gradient.type }, set: { store.editor.gradient.type = $0 })
    }
    private var reverseBinding: Binding<Bool> {
        Binding(get: { store.editor.gradient.reverse }, set: { store.editor.gradient.reverse = $0 })
    }
}
