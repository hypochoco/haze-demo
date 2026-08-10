//
//  CanvasView.swift
//  Haze — views/canvas
//

import SwiftUI

struct CanvasView: NSViewRepresentable {
    let store: Store
    let ui: AppUIState

    func makeNSView(context: Context) -> InputView { InputView(store: store, ui: ui) }
    func updateNSView(_ nsView: InputView, context: Context) {}
}
