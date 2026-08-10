//
//  Config.swift
//  Haze — config
//

import Foundation
import Combine

@MainActor
final class Config: ObservableObject {

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: History / undo
    var historyByteBudgetMB: Int {
        get { read("history.byteBudgetMB", 512) } set { write("history.byteBudgetMB", newValue) }
    }
    var tileSize: Int {
        get { read("history.tileSize", 256) } set { write("history.tileSize", newValue) }
    }
    var tilingEnabled: Bool {
        get { read("render.tilingEnabled", true) } set { write("render.tilingEnabled", newValue) }
    }

    // MARK: Brush defaults
    var brushDefaultSize: Double {
        get { read("brush.defaultSize", 24) } set { write("brush.defaultSize", newValue) }
    }
    var brushDefaultHardness: Double {
        get { read("brush.defaultHardness", 0.8) } set { write("brush.defaultHardness", newValue) }
    }

    // MARK: Colour
    var newCanvasDPI: Int {
        get { read("color.newCanvasDPI", 72) } set { write("color.newCanvasDPI", newValue) }
    }

    // MARK: Files
    var jpegQuality: Double {
        get { read("io.jpegQuality", 0.9) } set { write("io.jpegQuality", newValue) }
    }

    // MARK: Backing (typed get/set with defaults, publishing on change)
    private func read<T>(_ key: String, _ fallback: T) -> T {
        (defaults.object(forKey: key) as? T) ?? fallback
    }
    private func write<T>(_ key: String, _ value: T) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }
}
