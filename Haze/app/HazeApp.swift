//
//  HazeApp.swift
//  Haze — app
//

import SwiftUI
import AppKit
import OSLog

@main
struct HazeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.makeDefault()
    @StateObject private var panels = PanelVisibility(defaultVisible: PanelRegistry.defaultVisibleIDs)
    @StateObject private var panelOrder = PanelOrder()
    @StateObject private var ui = AppUIState()
    @StateObject private var brushPresets = BrushPresetStore()
    @StateObject private var brushTips = BrushTipStore()
    @StateObject private var keyBindings = KeyBindingStore()

    var body: some Scene {
        Window("Haze", id: "main-window") {
            MainWindowView(store: store, panels: panels, panelOrder: panelOrder, ui: ui, keyBindings: keyBindings)
                .environmentObject(brushPresets)
                .environmentObject(brushTips)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            Group {
                CommandGroup(replacing: .appSettings) { menuButton("app.settings") }
                CommandGroup(replacing: .newItem) { menuButton("file.new") }
                CommandGroup(replacing: .saveItem) {
                    menuButton("file.save")
                    menuButton("file.saveAs")
                    menuButton("file.open")
                    menuButton("file.export")
                    Divider()
                    menuButton("file.importBrushes")
                    menuButton("file.exportBrushes")
                    menuButton("brush.restoreDefaults")
                }
                CommandGroup(replacing: .undoRedo) {
                    menuButton("edit.undo")
                    menuButton("edit.redo")
                }
                CommandGroup(after: .undoRedo) {
                    Menu("Transform") {
                        menuButton("transform.flipH")
                        menuButton("transform.flipV")
                    }
                }
            }
            CommandMenu("Image") {
                menuButton("image.resize")
                Divider()
                menuButton("image.flipH"); menuButton("image.flipV")
            }
            CommandMenu("Tools") {
                toolItem("tool.brush")
                toolItem("tool.eraser")
                toolItem("tool.eyedropper")
                toolItem("tool.lasso")
                toolItem("tool.polygonLasso")
                Divider()
                toolItem("tool.move")
                toolItem("tool.transform")
                toolItem("tool.gradient")
                Divider()
                toolItem("brush.decreaseSize")
                toolItem("brush.increaseSize")
            }
            CommandMenu("Select") {
                menuButton("select.all")
                menuButton("select.none")
                menuButton("select.invert")
            }
            CommandMenu("Layer") {
                menuButton("layer.add")
                menuButton("layer.duplicate")
                menuButton("layer.delete")
                Divider()
                menuButton("layer.mergeDown")
                Divider()
                menuButton("layer.group")
                menuButton("layer.ungroup")
                Divider()
                menuButton("layer.toggleVisibility")
            }
            CommandGroup(after: .sidebar) {
                menuButton("view.commandPalette")
                Divider()
                menuButton("canvas.close")
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                ForEach(PanelRegistry.panels(for: .dockTrailing)) { spec in
                    Toggle(spec.title, isOn: Binding(
                        get: { panels.isVisible(spec.id) },
                        set: { panels.set(spec.id, $0) }))
                }
            }
            CommandGroup(replacing: .help) { menuButton("app.diagnostics") }
        }
    }

    private var actionContext: AppActionContext {
        AppActionContext(store: store, ui: ui, panels: panels, brushPresets: brushPresets, keyBindings: keyBindings)
    }

    @ViewBuilder
    private func toolItem(_ id: String) -> some View {
        menuButton(id).disabled(ui.isEditingText)
    }

    @ViewBuilder
    private func menuButton(_ id: String) -> some View {
        if let action = CommandRegistry.action(id) {
            let ctx = actionContext
            if let sc = ctx.keyBindings.effective(for: action) {
                Button(action.title) { action.run(ctx) }
                    .keyboardShortcut(sc.key, modifiers: sc.modifiers)
                    .disabled(!action.isEnabled(ctx))
            } else {
                Button(action.title) { action.run(ctx) }
                    .disabled(!action.isEnabled(ctx))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Haze launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { Self.confirmSaveBeforeQuit() }
    }

    @MainActor
    private static func confirmSaveBeforeQuit() -> NSApplication.TerminateReply {
        guard let store = Store.current, store.hasUnsavedChanges else { return .terminateNow }
        let dirty = Array(store.dirtyCanvasIDs)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = dirty.count == 1
            ? "You have unsaved changes. Save before quitting?"
            : "You have unsaved changes in \(dirty.count) canvases. Save before quitting?"
        alert.informativeText = "If you don’t save, your changes will be lost."
        alert.addButton(withTitle: dirty.count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for id in dirty {
                store.selectCanvas(id)
                PSDSaveCommand.save(store: store)
                if store.isDirty(id) { return .terminateCancel }
            }
            return store.hasUnsavedChanges ? .terminateCancel : .terminateNow
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
