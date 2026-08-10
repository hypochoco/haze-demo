//
//  CommandRegistry.swift
//  Haze — app/commands
//

import SwiftUI

@MainActor
enum CommandRegistry {

    // MARK: Static actions

    static let staticActions: [AppAction] = [
        AppAction(id: "edit.undo", title: "Undo", category: .edit,
                  shortcut: ActionShortcut("z"),
                  isEnabled: { $0.store.canUndo }, run: { $0.store.undo() }),
        AppAction(id: "edit.redo", title: "Redo", category: .edit, keywords: ["undo"],
                  shortcut: ActionShortcut("z", [.command, .shift]),
                  isEnabled: { $0.store.canRedo }, run: { $0.store.redo() }),

        AppAction(id: "file.new", title: "New Canvas…", category: .file, keywords: ["document"],
                  shortcut: ActionShortcut("n"), run: { $0.ui.showNewCanvas = true }),
        AppAction(id: "file.open", title: "Open…", category: .file, keywords: ["import", "png", "jpeg", "psd"],
                  shortcut: ActionShortcut("o"), run: { DocumentIOCommand.open(store: $0.store) }),
        AppAction(id: "file.save", title: "Save", category: .file,
                  shortcut: ActionShortcut("s"),
                  isEnabled: { $0.store.hasCanvas }, run: { PSDSaveCommand.save(store: $0.store) }),
        AppAction(id: "file.saveAs", title: "Save As…", category: .file,
                  shortcut: ActionShortcut("s", [.command, .shift]),
                  isEnabled: { $0.store.hasCanvas }, run: { PSDSaveCommand.saveAs(store: $0.store) }),
        AppAction(id: "file.export", title: "Export As…", category: .file,
                  keywords: ["png", "jpeg", "jpg", "image", "export"],
                  isEnabled: { $0.store.hasCanvas }, run: { DocumentIOCommand.exportAs(store: $0.store) }),
        AppAction(id: "file.importBrushes", title: "Import Brushes…", category: .file, keywords: ["preset"],
                  run: { BrushIOCommand.importBrushes(into: $0.brushPresets, store: $0.store) }),
        AppAction(id: "file.exportBrushes", title: "Export Brushes…", category: .file, keywords: ["preset"],
                  run: { BrushIOCommand.exportBrushes($0.brushPresets, store: $0.store) }),
        AppAction(id: "brush.restoreDefaults", title: "Restore Default Brushes", category: .file,
                  keywords: ["preset", "reset", "brushes", "built-in"],
                  run: { $0.brushPresets.restoreDefaults() }),

        AppAction(id: "image.resize", title: "Resize Canvas…", category: .image, keywords: ["scale", "size"],
                  shortcut: ActionShortcut("c", [.command, .option]),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.ui.showResizeCanvas = true }),
        AppAction(id: "image.flipH", title: "Flip Canvas Horizontally", category: .image, keywords: ["mirror", "flip", "horizontal"],
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.flipCanvas(horizontal: true) }),
        AppAction(id: "image.flipV", title: "Flip Canvas Vertically", category: .image, keywords: ["mirror", "flip", "vertical"],
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.flipCanvas(horizontal: false) }),

        AppAction(id: "tool.brush", title: "Brush Tool", category: .tool, keywords: ["paint", "draw"],
                  shortcut: ActionShortcut("b", []),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .brush }),
        AppAction(id: "tool.eraser", title: "Eraser Tool", category: .tool, keywords: ["erase", "rubber", "delete"],
                  shortcut: ActionShortcut("e", []),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .eraser }),
        AppAction(id: "tool.eyedropper", title: "Eyedropper Tool", category: .tool, keywords: ["colour", "color", "pick", "sample"],
                  shortcut: ActionShortcut("i", []),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .eyedropper }),
        AppAction(id: "tool.lasso", title: "Lasso Tool", category: .tool, keywords: ["select", "freehand"],
                  shortcut: ActionShortcut("l", []),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .lasso }),
        AppAction(id: "tool.polygonLasso", title: "Polygon Lasso Tool", category: .tool, keywords: ["select", "polygon"],
                  shortcut: ActionShortcut("l", [.shift]),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .polygonLasso }),
        AppAction(id: "tool.move", title: "Move Selection Tool", category: .tool, keywords: ["float", "reposition"],
                  shortcut: ActionShortcut("v", []),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .move }),
        AppAction(id: "tool.transform", title: "Free Transform Tool", category: .tool, keywords: ["scale", "rotate"],
                  shortcut: ActionShortcut("t", [.command]),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.editor.activeTool = .transform }),

        AppAction(id: "brush.decreaseSize", title: "Decrease Brush Size", category: .tool, keywords: ["smaller", "["],
                  shortcut: ActionShortcut("[", []),
                  isEnabled: { $0.store.hasCanvas }, run: { ctx in
                      let s = ctx.store.editor.brush.size
                      ctx.store.editor.brush.size = max(1, s - max(1, (s * 0.1).rounded()))
                  }),
        AppAction(id: "brush.increaseSize", title: "Increase Brush Size", category: .tool, keywords: ["bigger", "larger", "]"],
                  shortcut: ActionShortcut("]", []),
                  isEnabled: { $0.store.hasCanvas }, run: { ctx in
                      let s = ctx.store.editor.brush.size
                      ctx.store.editor.brush.size = min(300, s + max(1, (s * 0.1).rounded()))
                  }),

        AppAction(id: "transform.flipH", title: "Flip Horizontal", category: .edit, keywords: ["transform", "mirror"],
                  isEnabled: { $0.store.isTransforming }, run: { $0.store.flipTransform(horizontal: true) }),
        AppAction(id: "transform.flipV", title: "Flip Vertical", category: .edit, keywords: ["transform", "mirror"],
                  isEnabled: { $0.store.isTransforming }, run: { $0.store.flipTransform(horizontal: false) }),

        AppAction(id: "select.all", title: "Select All", category: .select, keywords: ["selection", "mask"],
                  shortcut: ActionShortcut("a"),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.selectAll() }),
        AppAction(id: "select.none", title: "Deselect", category: .select, keywords: ["selection", "clear", "none"],
                  shortcut: ActionShortcut("d"),
                  isEnabled: { $0.store.activeCanvas?.pixelSelection.isActive ?? false },
                  run: { $0.store.deselect() }),
        AppAction(id: "select.invert", title: "Invert Selection", category: .select, keywords: ["selection", "inverse"],
                  shortcut: ActionShortcut("i", [.command, .shift]),
                  isEnabled: { $0.store.activeCanvas?.pixelSelection.isActive ?? false },
                  run: { $0.store.invertSelection() }),

        AppAction(id: "layer.add", title: "Add Layer", category: .layer, keywords: ["new"],
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.addLayer() }),
        AppAction(id: "layer.duplicate", title: "Duplicate Layer", category: .layer, keywords: ["copy"],
                  isEnabled: { $0.store.activeCanvas?.selectedLayerID != nil },
                  run: { if let id = $0.store.activeCanvas?.selectedLayerID { $0.store.duplicateLayer(id) } }),
        AppAction(id: "layer.delete", title: "Delete Layer", category: .layer, keywords: ["remove"],
                  isEnabled: { $0.store.activeCanvas?.selectedLayerID != nil },
                  run: { if let id = $0.store.activeCanvas?.selectedLayerID { $0.store.removeLayer(id) } }),
        AppAction(id: "layer.mergeDown", title: "Merge Down", category: .layer,
                  keywords: ["merge", "combine", "flatten", "down"],
                  shortcut: ActionShortcut("e", [.command]),
                  isEnabled: { $0.store.canMergeDown },
                  run: { $0.store.mergeDown() }),
        AppAction(id: "layer.group", title: "Group Selection", category: .layer, keywords: ["folder"],
                  shortcut: ActionShortcut("g", [.command]),
                  isEnabled: { $0.store.hasCanvas }, run: { $0.store.groupSelected() }),
        AppAction(id: "layer.ungroup", title: "Ungroup", category: .layer, keywords: ["folder", "flatten", "dissolve"],
                  shortcut: ActionShortcut("g", [.command, .shift]),
                  isEnabled: { ctx in
                      guard let id = ctx.store.activeCanvas?.selectedLayerID else { return false }
                      return ctx.store.group(id) != nil
                  },
                  run: { if let id = $0.store.activeCanvas?.selectedLayerID { $0.store.ungroup(id) } }),
        AppAction(id: "layer.toggleVisibility", title: "Toggle Layer Visibility", category: .layer,
                  keywords: ["hide", "show", "eye", "visible"],
                  isEnabled: { $0.store.activeCanvas?.selectedLayerID != nil },
                  run: { ctx in
                      guard let id = ctx.store.activeCanvas?.selectedLayerID else { return }
                      if let g = ctx.store.group(id) { ctx.store.setGroupVisibility(id, !g.isVisible) }
                      else if let l = ctx.store.activeCanvas?.layer(id) { ctx.store.setLayerVisibility(id, !l.isVisible) }
                  }),

        AppAction(id: "view.commandPalette", title: "Command Palette…", category: .view, keywords: ["search", "run", "action"],
                  shortcut: ActionShortcut("p", [.command, .shift]), run: { $0.ui.showCommandPalette = true }),
        AppAction(id: "canvas.close", title: "Close Canvas", category: .view,
                  isEnabled: { $0.store.hasCanvas },
                  run: { if let c = $0.store.activeCanvas { CanvasCloseCommand.close(c.id, store: $0.store) } }),

        AppAction(id: "app.settings", title: "Settings…", category: .app, keywords: ["preferences", "config"],
                  shortcut: ActionShortcut(","), run: { $0.ui.showSettings = true }),
        AppAction(id: "app.diagnostics", title: "Reveal Diagnostics in Finder", category: .app, keywords: ["logs", "debug"],
                  run: { _ in DiagnosticsReport.revealInFinder() }),
    ]

    static var panelToggles: [AppAction] {
        PanelRegistry.panels(for: .dockTrailing).map { spec in
            AppAction(id: "view.toggle.\(spec.id.rawValue)",
                      title: "Toggle \(spec.title) Panel",
                      category: .view, keywords: ["panel", "show", "hide"],
                      run: { $0.panels.toggle(spec.id) })
        }
    }

    static var all: [AppAction] { staticActions + panelToggles }

    static func action(_ id: String) -> AppAction? { all.first { $0.id == id } }

    // MARK: Palette querying

    static func search(_ query: String, in ctx: AppActionContext) -> [AppAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return all.sorted {
                $0.category.order != $1.category.order ? $0.category.order < $1.category.order
                                                       : $0.title < $1.title
            }
        }
        return all
            .compactMap { a -> (AppAction, Int)? in
                let best = ([a.title] + a.keywords).compactMap { FuzzyMatch.score(trimmed, $0) }.max()
                return best.map { (a, $0) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }
            .map { $0.0 }
    }
}
