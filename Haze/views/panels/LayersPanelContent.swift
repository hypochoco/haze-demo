//
//  LayersPanelContent.swift
//  Haze — views/panels
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum DropSlot: Equatable { case above, below, into }
private struct DropHint: Equatable { let id: LayerID; let slot: DropSlot }

private struct LayerDropDelegate: DropDelegate {
    let target: LayerNode
    let rowH: CGFloat
    @Binding var dragging: LayerID?
    @Binding var hint: DropHint?
    let onPerform: (_ src: LayerID, _ target: LayerNode, _ slot: DropSlot) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) { hint = DropHint(id: target.id, slot: slot(info)) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hint = DropHint(id: target.id, slot: slot(info))
        return DropProposal(operation: dragging == target.id ? .forbidden : .move)
    }
    func dropExited(info: DropInfo) { if hint?.id == target.id { hint = nil } }
    func performDrop(info: DropInfo) -> Bool {
        guard let src = dragging else { return false }
        let s = slot(info); dragging = nil; hint = nil
        guard src != target.id else { return false }
        onPerform(src, target, s)
        return true
    }

    private func slot(_ info: DropInfo) -> DropSlot {
        let y = info.location.y
        if target.isGroup {
            if y < rowH * 0.33 { return .above }
            if y > rowH * 0.66 { return .below }
            return .into
        }
        return y < rowH * 0.5 ? .above : .below
    }
}

struct LayersPanelContent: View {
    @ObservedObject var store: Store
    @State private var opacityDragStart: Float?
    @State private var dragging: LayerID?
    @State private var dropHint: DropHint?
    @State private var renaming: LayerID?
    @State private var renameText: String = ""
    @FocusState private var renameFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var listEpoch = 0

    private var totalNodeCount: Int {
        func count(_ ns: [LayerNode]) -> Int {
            ns.reduce(0) { acc, n in
                if case .group(let g) = n { return acc + 1 + count(g.children) }
                return acc + 1
            }
        }
        return count(store.activeCanvas?.nodes ?? [])
    }

    private let rowH: CGFloat = 40
    private let groupRowH: CGFloat = 26
    private let indentStep: CGFloat = 14

    private func rows(_ nodes: [LayerNode], depth: Int) -> [(node: LayerNode, depth: Int)] {
        var out: [(LayerNode, Int)] = []
        for node in nodes.reversed() {
            out.append((node, depth))
            if case .group(let g) = node, g.isExpanded {
                out.append(contentsOf: rows(g.children, depth: depth + 1))
            }
        }
        return out
    }

    var body: some View {
        Group {
            if store.activeCanvas != nil {
                editorBody
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No canvas open").foregroundStyle(.secondary).font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            }
        }
    }

    private var editorBody: some View {
        VStack(spacing: 6) {
            opacityControl
            blendControl

            ScrollView {
                VStack(spacing: 2) {
                    let rowItems = rows(store.activeCanvas?.nodes ?? [], depth: 0)
                    if rowItems.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up.slash").font(.title2).foregroundStyle(.tertiary)
                            Text("No layers").foregroundStyle(.secondary).font(.callout)
                            Text("Add a layer to start painting.").foregroundStyle(.tertiary).font(.caption)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        ForEach(rowItems, id: \.node.id) { row in
                            nodeRow(row.node, depth: row.depth)
                        }
                    }
                }
                .id(listEpoch)
            }
            .frame(maxHeight: 320)
            .focusable()
            .focused($listFocused)
            .onChange(of: totalNodeCount) { old, new in
                clearDragState()
                if new < old { listEpoch &+= 1 }
            }
            .onKeyPress(.return) {
                guard renaming == nil, let sel = store.activeCanvas?.selectedLayerID else { return .ignored }
                beginRename(sel); return .handled
            }

            toolbar
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Opacity (selected leaf or group)

    @ViewBuilder
    private var opacityControl: some View {
        if let id = store.activeCanvas?.selectedLayerID, let value = selectedOpacity(id) {
            HStack(spacing: 6) {
                Text("Opacity").font(.caption)
                Slider(value: opacityBinding(id, current: value), in: 0...1) { editing in
                    if editing { opacityDragStart = selectedOpacity(id) }
                    else if let start = opacityDragStart {
                        if store.group(id) != nil { store.commitGroupOpacity(id, from: start) }
                        else { store.commitLayerOpacity(id, from: start) }
                        opacityDragStart = nil
                    }
                }
                Text(String(format: "%.0f%%", value * 100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func selectedOpacity(_ id: LayerID) -> Float? {
        store.activeCanvas?.layer(id)?.opacity ?? store.group(id)?.opacity
    }

    // MARK: - Blend mode (selected leaf or group)

    @ViewBuilder
    private var blendControl: some View {
        if let id = store.activeCanvas?.selectedLayerID, let current = selectedBlend(id) {
            HStack(spacing: 6) {
                Text("Blend").font(.caption)
                Picker("", selection: blendBinding(id, current: current)) {
                    ForEach(BlendMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }
        }
    }

    private func selectedBlend(_ id: LayerID) -> BlendMode? {
        store.activeCanvas?.layer(id)?.blend ?? store.group(id)?.blend
    }

    private func blendBinding(_ id: LayerID, current: BlendMode) -> Binding<BlendMode> {
        Binding(get: { selectedBlend(id) ?? current },
                set: { store.setBlend(id, $0) })
    }

    private func opacityBinding(_ id: LayerID, current: Float) -> Binding<Float> {
        Binding(get: { selectedOpacity(id) ?? current },
                set: { v in
                    if store.group(id) != nil { store.previewGroupOpacity(id, v) }
                    else { store.previewLayerOpacity(id, v) }
                })
    }

    // MARK: - Rows

    @ViewBuilder
    private func nodeRow(_ node: LayerNode, depth: Int) -> some View {
        let active = node.id == store.activeCanvas?.selectedLayerID || store.selection.contains(node.id)
        let rowHeight = node.isGroup ? groupRowH : rowH
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * indentStep, height: 1)
            switch node {
            case .group(let g):
                Button {
                    store.setGroupExpanded(g.id, !g.isExpanded)
                } label: {
                    Image(systemName: g.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).frame(width: 12)
                }.buttonStyle(.plain)
                Image(systemName: "folder.fill").foregroundStyle(.tertiary).frame(width: 36)
            case .layer(let l):
                leafThumbnails(l)
            }
            nameLabel(node)
            Spacer()
            visibilityButton(isVisible: node.isVisible) {
                if node.isGroup { store.setGroupVisibility(node.id, !node.isVisible) }
                else { store.setLayerVisibility(node.id, !node.isVisible) }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(active ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .top) { edgeIndicator(node, .above) }
        .overlay(alignment: .bottom) { edgeIndicator(node, .below) }
        .overlay { intoIndicator(node) }
        .contentShape(Rectangle())
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            clearDragState()
            listFocused = true
            if mods.contains(.shift) { store.extendSelection(to: node.id) }
            else if mods.contains(.command) { store.toggleSelection(node.id) }
            else { store.selectLayer(node.id) }
        }
        .contextMenu { layerMenu(node) }
        .onDrag {
            dragging = node.id
            return NSItemProvider(object: NSString(string: node.name))
        }
        .onDrop(of: [.text], delegate: LayerDropDelegate(
            target: node, rowH: rowHeight, dragging: $dragging, hint: $dropHint,
            onPerform: { src, target, slot in performMove(src, target, slot) }))
    }

    @ViewBuilder
    private func layerMenu(_ node: LayerNode) -> some View {
        Button("Rename") { beginRename(node.id) }
        Button(node.isVisible ? "Hide" : "Show") {
            if node.isGroup { store.setGroupVisibility(node.id, !node.isVisible) }
            else { store.setLayerVisibility(node.id, !node.isVisible) }
        }
        Divider()
        if case .layer = node {
            Button("Duplicate Layer") { structural { store.selectLayer(node.id); store.duplicateLayer(node.id) } }
            Button("Merge Down") { structural { store.selectLayer(node.id); store.mergeDown() } }
                .disabled(!store.canMergeDown(node.id))
        }
        if node.isGroup {
            Button("Ungroup") { structural { store.ungroup(node.id) } }
        } else {
            Button("Group") { structural { store.selectLayer(node.id); store.groupSelected() } }
        }
        Divider()
        Button("Delete Layer", role: .destructive) { structural { store.removeLayer(node.id) } }
            .disabled((store.activeCanvas?.layers.count ?? 0) <= 0)
    }

    private func structural(_ action: () -> Void) {
        clearDragState()
        action()
    }

    private func clearDragState() {
        if dragging != nil { dragging = nil }
        if dropHint != nil { dropHint = nil }
    }

    @ViewBuilder
    private func nameLabel(_ node: LayerNode) -> some View {
        if renaming == node.id {
            TextField("", text: $renameText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($renameFocused)
                .onSubmit { commitRename(node.id) }
                .onExitCommand { renaming = nil }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && renaming == node.id { commitRename(node.id) }
                }
                .onAppear { renameFocused = true }
        } else {
            Text(node.name)
                .font(.callout).lineLimit(1)
                .onTapGesture(count: 2) { beginRename(node.id) }
        }
    }

    private func beginRename(_ id: LayerID) {
        guard let name = store.activeCanvas?.layer(id)?.name ?? store.group(id)?.name else { return }
        renameText = name
        renaming = id
    }

    private func commitRename(_ id: LayerID) {
        store.renameNode(id, renameText)
        renaming = nil
    }

    // MARK: - Drag / drop

    private func performMove(_ src: LayerID, _ target: LayerNode, _ slot: DropSlot) {
        switch slot {
        case .into where target.isGroup: store.moveNode(src, intoGroup: target.id)
        case .above:                     store.moveNode(src, relativeTo: target.id, below: true)
        case .below, .into:              store.moveNode(src, relativeTo: target.id, below: false)
        }
    }

    @ViewBuilder
    private func edgeIndicator(_ node: LayerNode, _ slot: DropSlot) -> some View {
        if dropHint == DropHint(id: node.id, slot: slot) {
            Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func intoIndicator(_ node: LayerNode) -> some View {
        if dropHint == DropHint(id: node.id, slot: .into) {
            RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
        }
    }

    private func visibilityButton(isVisible: Bool, _ toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) { Image(systemName: isVisible ? "eye" : "eye.slash") }
            .buttonStyle(.plain)
            .foregroundStyle(isVisible ? .primary : .secondary)
    }

    @ViewBuilder
    private func thumbnail(_ layer: Layer) -> some View {
        LayerThumbnailView(store: store, layerID: layer.id)
    }

    @ViewBuilder
    private func leafThumbnails(_ layer: Layer) -> some View {
        let selected = layer.id == store.activeCanvas?.selectedLayerID
        thumbnail(layer)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .onTapGesture { store.selectLayer(layer.id) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { store.addLayer() } label: { Image(systemName: "plus.square") }.help("Add Layer")
            Button { store.groupSelected() } label: { Image(systemName: "folder.badge.plus") }
                .help("Group Selection")
            Button {
                if let s = store.activeCanvas?.selectedLayerID, store.group(s) != nil { store.ungroup(s) }
            } label: { Image(systemName: "folder.badge.minus") }
                .help("Ungroup")
                .disabled(!(store.activeCanvas?.selectedLayerID.map { store.group($0) != nil } ?? false))
            Divider().frame(height: 16)
            Button {
                if let s = store.activeCanvas?.selectedLayerID { store.duplicateLayer(s) }
            } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate Layer")
            Button { store.mergeDown() } label: { Image(systemName: "arrow.triangle.merge") }
                .help("Merge Down")
                .disabled(!store.canMergeDown)
            Button {
                if let s = store.activeCanvas?.selectedLayerID { store.removeLayer(s) }
            } label: { Image(systemName: "trash") }
                .help("Delete Layer")
                .disabled((store.activeCanvas?.layers.count ?? 0) <= 0)
            Spacer()
        }
        .buttonStyle(.plain)
    }
}
