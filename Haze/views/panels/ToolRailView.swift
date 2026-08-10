//
//  ToolRailView.swift
//  Haze — views/panels
//

import SwiftUI

struct ToolRailView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: AppUIState
    @ObservedObject var keyBindings: KeyBindingStore
    @State private var poppedID: PanelID?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ToolKind.allCases) { tool in
                railButton(tool.systemImage, active: store.editor.activeTool == tool) {
                    store.editor.activeTool = tool
                }
            }

            Spacer()

            ForEach(PanelRegistry.panels(for: .popover)) { spec in
                railButton(spec.systemImage, active: poppedID == spec.id) {
                    poppedID = (poppedID == spec.id) ? nil : spec.id
                }
                .popover(isPresented: Binding(get: { poppedID == spec.id },
                                              set: { if !$0 { poppedID = nil } })) {
                    spec.content(store).padding(12)
                }
            }

            railButton("gearshape", active: ui.showSettings) { ui.showSettings = true }
                .popover(isPresented: $ui.showSettings, arrowEdge: .leading) {
                    SettingsPanelContent(store: store, config: store.config, keyBindings: keyBindings).padding(16)
                }
        }
        .padding(.vertical, 8)
        .frame(width: 44)
        .background(.bar)
    }

    @ViewBuilder
    private func railButton(_ image: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(active ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}
