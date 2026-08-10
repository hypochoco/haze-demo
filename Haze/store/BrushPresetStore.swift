//
//  BrushPresetStore.swift
//  Haze — store
//

import Foundation
import Combine
import OSLog

@MainActor
final class BrushPresetStore: ObservableObject {
    @Published private(set) var presets: [BrushPreset]
    @Published var selectedID: BrushPreset.ID?

    private let fileURL: URL?

    init(directory: URL? = BrushPresetStore.defaultDirectory()) {
        self.fileURL = directory?.appendingPathComponent("library.json")
        if let url = fileURL, let loaded = Self.load(url) {
            presets = loaded
        } else {
            presets = Self.builtIns()
            save()
        }
    }

    // MARK: - Derived

    var selected: BrushPreset? { presets.first { $0.id == selectedID } }

    func isDirty(against brush: BrushSettings) -> Bool {
        guard let sel = selected else { return false }
        return !brush.equalsIgnoringColor(sel.settings)
    }

    func settingsApplying(_ preset: BrushPreset, keepingColorOf brush: BrushSettings) -> BrushSettings {
        brush.applying(preset: preset.settings)
    }

    // MARK: - Mutations (all persist)

    @discardableResult
    func saveNew(from brush: BrushSettings) -> BrushPreset {
        let preset = BrushPreset(name: generatedName(for: brush), settings: brush)
        presets.append(preset)
        selectedID = preset.id
        save()
        return preset
    }

    func delete(_ id: BrushPreset.ID) {
        presets.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        save()
    }

    func rename(_ id: BrushPreset.ID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = trimmed
        save()
    }

    func updateFromCurrent(_ id: BrushPreset.ID, with brush: BrushSettings) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].settings = brush.presetFields()
        save()
    }

    @discardableResult
    func duplicate(_ id: BrushPreset.ID) -> BrushPreset? {
        guard let src = presets.first(where: { $0.id == id }) else { return nil }
        let copy = BrushPreset(name: uniqueName(src.name + " copy"), settings: src.settings)
        if let i = presets.firstIndex(where: { $0.id == id }) { presets.insert(copy, at: i + 1) }
        else { presets.append(copy) }
        selectedID = copy.id
        save()
        return copy
    }

    func restoreDefaults() {
        for b in Self.builtIns() where !presets.contains(where: { $0.name == b.name }) {
            presets.append(b)
        }
        save()
    }

    @discardableResult
    func merge(_ imported: [BrushPreset]) -> Int {
        for p in imported {
            presets.append(BrushPreset(name: uniqueName(p.name), settings: p.settings))
        }
        if !imported.isEmpty { save() }
        return imported.count
    }

    // MARK: - Naming

    private func generatedName(for brush: BrushSettings) -> String {
        let word = brush.flow < 0.4 ? "Airbrush" : (brush.hardness >= 0.66 ? "Round" : "Soft")
        return uniqueName("\(word) \(Int(brush.size.rounded()))")
    }

    private func uniqueName(_ base: String) -> String {
        guard presets.contains(where: { $0.name == base }) else { return base }
        var n = 2
        while presets.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: - Built-ins (Round + Airbrush)

    static func builtIns() -> [BrushPreset] {
        var round = BrushSettings()
        round.size = 24; round.hardness = 0.9; round.spacing = 0.1; round.flow = 1; round.opacity = 1

        var air = BrushSettings()
        air.size = 60; air.hardness = 0.0; air.spacing = 0.04; air.flow = 0.15; air.opacity = 1
        air.pressureFlow = 0.5

        return [BrushPreset(name: "Round", settings: round, builtIn: true),
                BrushPreset(name: "Airbrush", settings: air, builtIn: true)]
    }

    // MARK: - Persistence (JSON envelope, atomic)

    nonisolated static func defaultDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Haze/Brushes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try Self.encodeLibrary(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.app.error("Brush library save failed: \(String(describing: error))")
        }
    }

    private static func load(_ url: URL) -> [BrushPreset]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decodeLibrary(data)
    }

    static func encodeLibrary(_ presets: [BrushPreset]) throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(BrushLibraryFile(presets: presets))
    }

    static func decodeLibrary(_ data: Data) throws -> [BrushPreset] {
        try JSONDecoder().decode(BrushLibraryFile.self, from: data).presets
    }
}
