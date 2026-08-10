//
//  HistoryDebugInfo.swift
//  Haze — history
//

struct HistoryDebugInfo {
    struct Entry: Identifiable {
        let index: Int
        let title: String
        let byteCost: Int
        var id: Int { index }
    }

    let canvasName: String
    let undo: [Entry]
    let redo: [Entry]
    let byteCount: Int
    let byteBudget: Int

    var undoDepth: Int { undo.count }
    var redoDepth: Int { redo.count }
    var budgetFraction: Double {
        guard byteBudget > 0, byteBudget != .max else { return 0 }
        return min(1, Double(byteCount) / Double(byteBudget))
    }

    static let empty = HistoryDebugInfo(canvasName: "—", undo: [], redo: [],
                                        byteCount: 0, byteBudget: 0)
}
