//
//  PanelOrder.swift
//  Haze — panels
//

import Foundation
import Combine

@MainActor
final class PanelOrder: ObservableObject {
    @Published private(set) var order: [PanelID]

    private let defaults: UserDefaults
    private let key = "panels.order"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: key) as? [String] {
            order = stored.map(PanelID.init(_:))
        } else {
            order = []
        }
    }

    func ordered(_ ids: [PanelID]) -> [PanelID] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.enumerated().sorted { l, r in
            switch (rank[l.element], rank[r.element]) {
            case let (a?, b?): return a < b
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return l.offset < r.offset
            }
        }.map(\.element)
    }

    func move(_ dragged: PanelID, to target: PanelID, allIDs: [PanelID]) {
        guard dragged != target else { return }
        var full = ordered(allIDs)
        guard let from = full.firstIndex(of: dragged),
              let origTo = full.firstIndex(of: target) else { return }
        full.remove(at: from)
        guard let now = full.firstIndex(of: target) else { return }
        let insertAt = from < origTo ? now + 1 : now
        full.insert(dragged, at: insertAt)
        setOrder(full)
    }

    private func setOrder(_ newOrder: [PanelID]) {
        order = newOrder
        defaults.set(newOrder.map(\.rawValue), forKey: key)
    }
}
