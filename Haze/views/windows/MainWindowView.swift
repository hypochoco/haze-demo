//
//  MainWindowView.swift
//  Haze — views/windows
//

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: Store
    @ObservedObject var panels: PanelVisibility
    @ObservedObject var panelOrder: PanelOrder
    @ObservedObject var ui: AppUIState
    @ObservedObject var keyBindings: KeyBindingStore
    @EnvironmentObject var brushPresets: BrushPresetStore

    private var actionContext: AppActionContext {
        AppActionContext(store: store, ui: ui, panels: panels, brushPresets: brushPresets, keyBindings: keyBindings)
    }

    var body: some View {
        Group {
            if ui.showWelcome && !store.hasCanvas {
                WelcomeView(store: store, ui: ui)
            } else {
                editorLayout
            }
        }
        .onChange(of: store.hasCanvas) { _, has in if has { ui.showWelcome = false } }
        .overlay { NoticeOverlay(center: store.notices) }
        .overlay {
            if ui.showCommandPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { ui.showCommandPalette = false }
                    CommandPaletteView(ctx: actionContext, isPresented: $ui.showCommandPalette)
                        .padding(.top, 96)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $ui.showNewCanvas) {
            NewCanvasSheet(store: store, isPresented: $ui.showNewCanvas)
        }
        .sheet(isPresented: $ui.showResizeCanvas) {
            ResizeCanvasSheet(store: store, isPresented: $ui.showResizeCanvas)
        }
    }

    private var editorLayout: some View {
        HStack(spacing: 0) {
            ToolRailView(store: store, ui: ui, keyBindings: keyBindings)
            Divider()
            VStack(spacing: 0) {
                DocumentTabBar(store: store, ui: ui)
                Divider()
                CanvasView(store: store, ui: ui)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            let dockPanels = PanelRegistry.panels(for: .dockTrailing).filter { panels.isVisible($0.id) }
            if !dockPanels.isEmpty {
                Divider()
                DockView(store: store, visibility: panels, order: panelOrder)
            }
        }
    }
}
