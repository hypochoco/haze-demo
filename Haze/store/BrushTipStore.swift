//
//  BrushTipStore.swift
//  Haze — store
//

import Foundation
import Combine

@MainActor
final class BrushTipStore: ObservableObject {
    var allTips: [BrushTip] { BrushTipCatalog.builtIns }

    func tip(_ id: UUID?) -> BrushTip? { BrushTipCatalog.tip(id) }
}
