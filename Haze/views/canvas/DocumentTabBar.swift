//
//  DocumentTabBar.swift
//  Haze — views/canvas
//

import SwiftUI

struct DocumentTabBar: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: AppUIState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.document.canvases, id: \.id) { canvas in
                chip(canvas)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private func chip(_ canvas: Canvas) -> some View {
        let active = canvas.id == store.document.activeCanvasID
        HStack(spacing: 6) {
            if store.isDirty(canvas.id) {
                Circle().fill(.secondary).frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
            Text(canvas.name).font(.callout).lineLimit(1)
            Button { CanvasCloseCommand.close(canvas.id, store: store) } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Canvas")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { store.selectCanvas(canvas.id) }
    }
}
