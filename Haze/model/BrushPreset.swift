//
//  BrushPreset.swift
//  Haze — model
//

import Foundation

struct BrushPreset: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var settings: BrushSettings
    var builtIn: Bool

    init(id: UUID = UUID(), name: String, settings: BrushSettings, builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.settings = settings.presetFields()
        self.builtIn = builtIn
    }
}

struct BrushLibraryFile: Codable {
    static let currentVersion = 1
    var version: Int = BrushLibraryFile.currentVersion
    var presets: [BrushPreset]
}
