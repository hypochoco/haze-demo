//
//  AppAction.swift
//  Haze — app/commands
//

import SwiftUI
import AppKit

enum ActionCategory: String, CaseIterable {
    case file, edit, image, tool, select, layer, view, app
    var title: String {
        switch self {
        case .file: return "File"
        case .edit: return "Edit"
        case .image: return "Image"
        case .tool: return "Tool"
        case .select: return "Select"
        case .layer: return "Layer"
        case .view: return "View"
        case .app: return "App"
        }
    }
    var order: Int { ActionCategory.allCases.firstIndex(of: self) ?? 0 }
}

struct ActionShortcut: Equatable, Hashable {
    let key: KeyEquivalent
    let modifiers: EventModifiers

    init(_ key: KeyEquivalent, _ modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    private static let ordered: [(EventModifiers, String)] =
        [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]

    var token: String {
        var parts = Self.ordered.compactMap { modifiers.contains($0.0) ? $0.1 : nil }
        parts.append(String(key.character).lowercased())
        return parts.joined(separator: "+")
    }

    init?(token: String) {
        let parts = token.split(separator: "+").map(String.init)
        guard let last = parts.last, last.count == 1, let ch = last.first else { return nil }
        var mods: EventModifiers = []
        for p in parts.dropLast() {
            guard let m = Self.ordered.first(where: { $0.1 == p })?.0 else { return nil }
            mods.insert(m)
        }
        self.init(KeyEquivalent(ch), mods)
    }

    init?(event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers,
              let ch = chars.lowercased().first else { return nil }
        var mods: EventModifiers = []
        let f = event.modifierFlags
        if f.contains(.control) { mods.insert(.control) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.command) { mods.insert(.command) }
        self.init(KeyEquivalent(ch), mods)
    }

    func matches(_ event: NSEvent) -> Bool { ActionShortcut(event: event) == self }

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += String(key.character).uppercased()
        return s
    }

    static func == (a: ActionShortcut, b: ActionShortcut) -> Bool {
        a.key.character == b.key.character && a.modifiers == b.modifiers
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(key.character)
        hasher.combine(modifiers.rawValue)
    }
}

@MainActor
struct AppActionContext {
    let store: Store
    let ui: AppUIState
    let panels: PanelVisibility
    let brushPresets: BrushPresetStore
    let keyBindings: KeyBindingStore

    func shortcut(for action: AppAction) -> ActionShortcut? { keyBindings.effective(for: action) }
}

@MainActor
struct AppAction: Identifiable {
    let id: String
    let title: String
    let category: ActionCategory
    var keywords: [String] = []
    var shortcut: ActionShortcut? = nil
    var isEnabled: (AppActionContext) -> Bool = { _ in true }
    let run: (AppActionContext) -> Void
}
