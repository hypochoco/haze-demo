//
//  KeyBindingStore.swift
//  Haze — config
//

import Foundation
import Combine

@MainActor
final class KeyBindingStore: ObservableObject {

    private let defaults: UserDefaults
    private static let prefix = "keybind."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ id: String) -> String { Self.prefix + id }

    // MARK: Effective resolution

    func effective(for action: AppAction) -> ActionShortcut? {
        guard let token = defaults.string(forKey: key(action.id)) else { return action.shortcut }
        if token.isEmpty { return nil }
        return ActionShortcut(token: token) ?? action.shortcut
    }

    func effective(id: String) -> ActionShortcut? {
        CommandRegistry.action(id).flatMap { effective(for: $0) }
    }

    // MARK: Mutation

    func setShortcut(_ shortcut: ActionShortcut?, for id: String) {
        objectWillChange.send()
        defaults.set(shortcut?.token ?? "", forKey: key(id))
    }

    func reset(_ id: String) {
        objectWillChange.send()
        defaults.removeObject(forKey: key(id))
    }

    func resetAll() {
        objectWillChange.send()
        for a in CommandRegistry.all { defaults.removeObject(forKey: key(a.id)) }
    }

    func isCustomized(_ id: String) -> Bool { defaults.object(forKey: key(id)) != nil }

    // MARK: Conflicts

    func conflict(for shortcut: ActionShortcut, excluding id: String) -> AppAction? {
        CommandRegistry.all.first { $0.id != id && effective(for: $0) == shortcut }
    }
}
