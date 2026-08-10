//
//  HistoryDebugPanelContent.swift
//  Haze — views/panels
//

import SwiftUI

struct HistoryDebugPanelContent: View {
    @ObservedObject var store: Store

    var body: some View {
        let info = store.historyDebugInfo
        VStack(alignment: .leading, spacing: 8) {
            header(info)
            budgetBar(info)
            Divider()
            timeline(info)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header + budget

    private func header(_ info: HistoryDebugInfo) -> some View {
        HStack {
            Label(info.canvasName, systemImage: "clock.arrow.circlepath")
                .lineLimit(1)
            Spacer()
            Text("↶\(info.undoDepth) ↷\(info.redoDepth)")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    @ViewBuilder
    private func budgetBar(_ info: HistoryDebugInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.bytes(info.byteCount)).monospacedDigit()
                Text("/").foregroundStyle(.tertiary)
                Text(info.byteBudget == .max ? "∞" : Self.bytes(info.byteBudget))
                    .foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if info.budgetFraction > 0 {
                    Text(String(format: "%.0f%%", info.budgetFraction * 100))
                        .foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            if info.budgetFraction > 0 {
                ProgressView(value: info.budgetFraction)
                    .tint(info.budgetFraction > 0.9 ? .orange : .accentColor)
            }
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private func timeline(_ info: HistoryDebugInfo) -> some View {
        if info.undo.isEmpty && info.redo.isEmpty {
            Text("No history yet.").foregroundStyle(.tertiary).padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(info.redo.reversed()) { entryRow($0, symbol: "arrow.uturn.forward", dim: true) }
                    HStack(spacing: 6) {
                        Image(systemName: "smallcircle.filled.circle").foregroundStyle(.tint)
                        Text("current").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                    ForEach(info.undo.reversed()) { entryRow($0, symbol: "arrow.uturn.backward", dim: false) }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func entryRow(_ e: HistoryDebugInfo.Entry, symbol: String, dim: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(.tertiary).frame(width: 12)
            Text(e.title).lineLimit(1)
            Spacer()
            Text(Self.bytes(e.byteCost)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .opacity(dim ? 0.5 : 1)
    }

    // MARK: Bytes

    static func bytes(_ n: Int) -> String {
        if n >= 1 << 20 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        if n >= 1 << 10 { return String(format: "%.0f KB", Double(n) / 1024) }
        return "\(n) B"
    }
}
