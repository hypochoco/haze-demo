//
//  PanelVisibility.swift
//  Haze — panels
//

import Foundation
import Combine

@MainActor
final class PanelVisibility: ObservableObject {
    @Published private(set) var visible: Set<PanelID>

    private let defaults: UserDefaults
    private let key = "panels.visible"

    init(defaultVisible: Set<PanelID>, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: key) as? [String] {
            visible = Set(stored.map(PanelID.init(_:)))
        } else {
            visible = defaultVisible
        }
    }

    func isVisible(_ id: PanelID) -> Bool { visible.contains(id) }

    func set(_ id: PanelID, _ on: Bool) {
        if on { visible.insert(id) } else { visible.remove(id) }
        persist()
    }

    func toggle(_ id: PanelID) { set(id, !isVisible(id)) }

    private func persist() {
        defaults.set(visible.map(\.rawValue), forKey: key)
    }
}
