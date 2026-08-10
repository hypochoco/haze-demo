//
//  EditorState.swift
//  Haze — store
//

struct EditorState: Equatable {
    var activeTool: ToolKind = .brush

    private var paintSettings: [ToolKind: BrushSettings] = [:]

    subscript(paint tool: ToolKind) -> BrushSettings {
        get { paintSettings[tool] ?? tool.defaultPaintSettings }
        set { paintSettings[tool] = newValue }
    }

    var brush: BrushSettings {
        get { self[paint: activeTool.paintSlot] }
        set { self[paint: activeTool.paintSlot] = newValue }
    }
}
