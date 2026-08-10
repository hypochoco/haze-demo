//
//  DockView.swift
//  Haze — views/panels
//

import SwiftUI
import UniformTypeIdentifiers

private struct PanelDropHint: Equatable { let target: PanelID; let below: Bool }

struct DockView: View {
    @ObservedObject var store: Store
    @ObservedObject var visibility: PanelVisibility
    @ObservedObject var order: PanelOrder

    @State private var dragging: PanelID?
    @State private var hint: PanelDropHint?
    @State private var epoch = 0

    var body: some View {
        let allDockIDs = PanelRegistry.panels(for: .dockTrailing).map(\.id)
        let fullOrdered = order.ordered(allDockIDs)
        let panels = fullOrdered
            .compactMap { PanelRegistry.spec($0) }
            .filter { visibility.isVisible($0.id) }

        ScrollView {
            VStack(spacing: 8) {
                ForEach(panels) { spec in
                    PanelChrome(title: spec.title, dragHandle: AnyView(handle(for: spec.id))) {
                        spec.content(store)
                    }
                    .opacity(dragging == spec.id ? 0.5 : 1)
                    .overlay(alignment: .top) { insertionLine(if: hint?.target == spec.id && hint?.below == false, edge: .top) }
                    .overlay(alignment: .bottom) { insertionLine(if: hint?.target == spec.id && hint?.below == true, edge: .bottom) }
                    .onDrop(of: [.text], delegate: PanelDropDelegate(
                        target: spec.id, fullOrdered: fullOrdered,
                        dragging: $dragging, hint: $hint,
                        onReorder: { src, tgt in order.move(src, to: tgt, allIDs: allDockIDs) }))
                }
            }
            .padding(8)
            .id(epoch)
            .animation(.easeInOut(duration: 0.18), value: order.order)
        }
        .frame(width: 264)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: panels.count) { oldCount, newCount in
            if newCount < oldCount { epoch += 1; dragging = nil; hint = nil }
        }
    }

    private func handle(for id: PanelID) -> some View {
        HStack(spacing: 2.5) {
            VStack(spacing: 2.5) { gripDot; gripDot; gripDot }
            VStack(spacing: 2.5) { gripDot; gripDot; gripDot }
        }
        .padding(4)
        .contentShape(Rectangle())
        .modifier(GrabCursorStyle())
        .onDrag {
            dragging = id
            return NSItemProvider(object: id.rawValue as NSString)
        }
        .help("Drag to reorder")
    }

    private var gripDot: some View { Circle().fill(.secondary).frame(width: 2, height: 2) }

    @ViewBuilder
    private func insertionLine(if show: Bool, edge: VerticalEdge) -> some View {
        if show {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 6)
                .offset(y: edge == .top ? -5 : 5)
        }
    }
}

private struct PanelDropDelegate: DropDelegate {
    let target: PanelID
    let fullOrdered: [PanelID]
    @Binding var dragging: PanelID?
    @Binding var hint: PanelDropHint?
    let onReorder: (_ dragged: PanelID, _ target: PanelID) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) { updateHint() }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHint()
        return DropProposal(operation: dragging == target ? .forbidden : .move)
    }
    func dropExited(info: DropInfo) { if hint?.target == target { hint = nil } }
    func performDrop(info: DropInfo) -> Bool {
        guard let src = dragging else { return false }
        dragging = nil; hint = nil
        guard src != target else { return false }
        onReorder(src, target)
        return true
    }

    private func updateHint() {
        guard let d = dragging, d != target else { hint = nil; return }
        let below = (fullOrdered.firstIndex(of: d) ?? 0) < (fullOrdered.firstIndex(of: target) ?? 0)
        hint = PanelDropHint(target: target, below: below)
    }
}

private struct GrabCursorStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.grabIdle)
        } else {
            content
        }
    }
}
