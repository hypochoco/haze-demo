//
//  SettingsCatalog.swift
//  Haze — config
//

import Foundation

enum SettingCategory: String, CaseIterable, Identifiable {
    case brush = "Brush"
    case color = "Colour"
    case history = "History"
    case rendering = "Rendering"
    case files = "Files"

    var id: String { rawValue }
    var order: Int {
        switch self {
        case .brush: return 0
        case .color: return 1
        case .history: return 2
        case .rendering: return 3
        case .files: return 4
        }
    }
}

enum SettingControl {
    case toggle(get: @MainActor (Config) -> Bool,
                set: @MainActor (Config, Bool) -> Void)
    case intStepper(range: ClosedRange<Int>, step: Int,
                    get: @MainActor (Config) -> Int,
                    set: @MainActor (Config, Int) -> Void)
    case doubleSlider(range: ClosedRange<Double>, step: Double,
                      get: @MainActor (Config) -> Double,
                      set: @MainActor (Config, Double) -> Void)
}

struct SettingDescriptor: Identifiable {
    let id: String
    let title: String
    let help: String
    let category: SettingCategory
    let control: SettingControl
    var requiresRelaunch: Bool = false
}

@MainActor
enum SettingsCatalog {
    static let all: [SettingDescriptor] = [
        SettingDescriptor(
            id: "color.newCanvasDPI",
            title: "New canvas resolution (DPI)",
            help: "Default print resolution for new canvases. Metadata only — it does not change pixel dimensions, but it round-trips through PSD.",
            category: .color,
            control: .intStepper(range: 72...600, step: 1,
                                 get: { $0.newCanvasDPI },
                                 set: { $0.newCanvasDPI = $1 })),

        SettingDescriptor(
            id: "io.jpegQuality",
            title: "JPEG export quality",
            help: "Quality for JPEG export (higher = larger files, fewer artefacts). Lossless formats (PNG/PSD) ignore this.",
            category: .files,
            control: .doubleSlider(range: 0.1...1.0, step: 0.05,
                                   get: { $0.jpegQuality },
                                   set: { $0.jpegQuality = $1 })),

        SettingDescriptor(
            id: "history.byteBudgetMB",
            title: "Undo memory budget (MB)",
            help: "Memory the undo history may use before the oldest steps are evicted. Applies immediately.",
            category: .history,
            control: .intStepper(range: 64...8192, step: 64,
                                 get: { $0.historyByteBudgetMB },
                                 set: { $0.historyByteBudgetMB = $1 })),

        SettingDescriptor(
            id: "render.tilingEnabled",
            title: "Sparse tiled storage",
            help: "Store each layer as sparse tiles — far less memory on large, mostly-empty canvases.",
            category: .rendering,
            control: .toggle(get: { $0.tilingEnabled },
                             set: { $0.tilingEnabled = $1 }),
            requiresRelaunch: true),

        SettingDescriptor(
            id: "history.tileSize",
            title: "Tile size (px)",
            help: "Edge length of the tiles used for layer storage and undo diffs.",
            category: .rendering,
            control: .intStepper(range: 64...512, step: 64,
                                 get: { $0.tileSize },
                                 set: { $0.tileSize = $1 }),
            requiresRelaunch: true),
    ]

    static var grouped: [(category: SettingCategory, items: [SettingDescriptor])] {
        Dictionary(grouping: all, by: \.category)
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.order < $1.category.order }
    }
}
