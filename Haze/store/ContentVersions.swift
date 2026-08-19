//
//  ContentVersions.swift
//  Haze — store
//

import Combine

@MainActor
final class ContentVersions: ObservableObject {
    @Published private(set) var versions: [LayerID: Int] = [:]
    private var seq = 0

    func version(_ id: LayerID) -> Int { versions[id] ?? 0 }

    func bump(_ ids: [LayerID]) {
        guard !ids.isEmpty else { return }
        for id in ids { seq += 1; versions[id] = seq }
    }
}
