//
//  PanelRegistry.swift
//  Haze — views/panels
//

import SwiftUI

@MainActor
enum PanelRegistry {
    static let all: [PanelSpec] = {
        var specs: [PanelSpec] = [
            PanelSpec(id: .color, title: "Color", systemImage: "paintpalette",
                      placement: .dockTrailing, defaultVisible: true) { store in
                AnyView(ColorPanelContent(store: store))
            },
            PanelSpec(id: .brush, title: "Brush", systemImage: "paintbrush.pointed.fill",
                      placement: .dockTrailing, defaultVisible: true) { store in
                AnyView(BrushPanelContent(store: store))
            },
            PanelSpec(id: .layers, title: "Layers", systemImage: "square.3.layers.3d",
                      placement: .dockTrailing, defaultVisible: true) { store in
                AnyView(LayersPanelContent(store: store))
            },
            PanelSpec(id: .gradient, title: "Gradient", systemImage: "circle.lefthalf.filled",
                      placement: .dockTrailing, defaultVisible: false) { store in
                AnyView(GradientPanelContent(store: store))
            },
            PanelSpec(id: .info, title: "Info", systemImage: "info.circle",
                      placement: .popover, defaultVisible: false) { store in
                AnyView(InfoPanelContent(store: store))
            },
        ]
        #if DEBUG
        specs.append(PanelSpec(id: .historyDebug, title: "History (debug)", systemImage: "ladybug",
                               placement: .dockTrailing, defaultVisible: false) { store in
            AnyView(HistoryDebugPanelContent(store: store))
        })
        #endif
        return specs
    }()

    static func panels(for placement: PanelPlacement) -> [PanelSpec] {
        all.filter { $0.placement == placement }
    }

    static func spec(_ id: PanelID) -> PanelSpec? { all.first { $0.id == id } }

    static var defaultVisibleIDs: Set<PanelID> { Set(all.filter(\.defaultVisible).map(\.id)) }
}
