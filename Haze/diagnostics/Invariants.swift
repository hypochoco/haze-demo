//
//  Invariants.swift
//  Haze — diagnostics
//

import Foundation
import OSLog

enum Invariants {

    @inline(__always)
    static func require(_ condition: @autoclosure () -> Bool,
                        _ message: @autoclosure () -> String,
                        file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        if !condition() {
            let msg = message()
            Log.app.fault("Invariant violated: \(msg, privacy: .public)")
            assertionFailure(msg, file: file, line: line)
        }
        #endif
    }
}

@MainActor
extension Invariants {

    static func treeViolations(_ canvas: Canvas, selection: Set<LayerID>) -> [String] {
        var out: [String] = []
        let ids = canvas.nodes.allNodeIDs()
        var seen = Set<LayerID>(); var dupes = Set<LayerID>()
        for id in ids where !seen.insert(id).inserted { dupes.insert(id) }
        if !dupes.isEmpty { out.append("duplicate node ids (\(dupes.count))") }
        let idSet = Set(ids)
        if let sel = canvas.selectedLayerID, !idSet.contains(sel) { out.append("selectedLayerID absent from tree") }
        let stray = selection.subtracting(idSet)
        if !stray.isEmpty { out.append("selection has \(stray.count) id(s) absent from tree") }
        return out
    }

    static func checkTree(_ canvas: Canvas, file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        let v = treeViolations(canvas, selection: [])
        require(v.isEmpty, "layer tree: \(v.joined(separator: "; "))", file: file, line: line)
        #endif
    }
}
