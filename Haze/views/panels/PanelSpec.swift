//
//  PanelSpec.swift
//  Haze — views/panels
//

import SwiftUI

struct PanelSpec: Identifiable {
    let id: PanelID
    let title: String
    let systemImage: String
    let placement: PanelPlacement
    let defaultVisible: Bool
    let content: @MainActor (Store) -> AnyView
}
