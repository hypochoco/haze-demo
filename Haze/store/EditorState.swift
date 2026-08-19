//
//  EditorState.swift
//  Haze — store
//

import Combine

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


@MainActor
final class EditorStore: ObservableObject {
    @Published var state = EditorState()
}
