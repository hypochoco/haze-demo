//
//  Store+Layer.swift
//  Haze — commands
//

import Foundation

extension Store {

    // MARK: - Groups (structural; no pixels → MutateCommand)

    func addGroup(name: String? = nil) {
        guard let canvas = requireCanvas("Add Group") else { return }
        let group = LayerGroup(name: name ?? nextName("Group", in: canvas))
        let previousSelection = canvas.selectedLayerID
        perform(MutateCommand(
            title: "Add Group",
            doApply: { ctx in ctx.canvas.nodes.append(.group(group)); ctx.canvas.selectedLayerID = group.id },
            doRevert: { ctx in ctx.canvas.nodes.removeByID(group.id); ctx.canvas.selectedLayerID = previousSelection }))
    }

    func groupSelected(name: String? = nil) {
        guard let canvas = requireCanvas("Group") else { return }
        let groupName = name ?? nextName("Group", in: canvas)
        let ids = selection.count > 1 ? selection : Set(canvas.selectedLayerID.map { [$0] } ?? [])
        let picks = ids.compactMap { id -> (index: Int, node: LayerNode)? in
            canvas.nodes.firstTopLevelIndex(of: id).map { ($0, canvas.nodes[$0]) }
        }.sorted { $0.index < $1.index }

        if picks.count <= 1, selection.count <= 1, let sel = canvas.selectedLayerID,
           let path = canvas.nodes.indexPath(of: sel),
           let node = canvas.nodes.node(atPath: path) {
            let group = LayerGroup(name: groupName, children: [node])
            perform(MutateCommand(
                title: "Group",
                doApply: { ctx in
                    guard let p = ctx.canvas.nodes.indexPath(of: sel) else { return }
                    ctx.canvas.nodes.removeNode(atPath: p)
                    ctx.canvas.nodes.insertNode(.group(group), atPath: p)
                    ctx.canvas.selectedLayerID = group.id
                },
                doRevert: { ctx in
                    guard let p = ctx.canvas.nodes.indexPath(of: group.id) else { return }
                    ctx.canvas.nodes.removeNode(atPath: p)
                    ctx.canvas.nodes.insertNode(node, atPath: p)
                    ctx.canvas.selectedLayerID = sel
                }))
            selection = [group.id]
            return
        }

        guard !picks.isEmpty else { notices.post("Select a layer to group", .warning); return }

        let minIndex = picks[0].index
        let nodes = picks.map(\.node)
        let originalIndices = picks.map(\.index)
        let group = LayerGroup(name: groupName, children: nodes)
        perform(MutateCommand(
            title: "Group",
            doApply: { ctx in
                for n in nodes { ctx.canvas.nodes.removeByID(n.id) }
                ctx.canvas.nodes.insert(.group(group), at: min(minIndex, ctx.canvas.nodes.count))
                ctx.canvas.selectedLayerID = group.id
            },
            doRevert: { ctx in
                ctx.canvas.nodes.removeByID(group.id)
                for (k, n) in nodes.enumerated() {
                    ctx.canvas.nodes.insert(n, at: min(originalIndices[k], ctx.canvas.nodes.count))
                }
                ctx.canvas.selectedLayerID = nodes.first?.id
            }))
        selection = [group.id]
    }

    func ungroup(_ id: LayerID) {
        guard let canvas = requireCanvas("Ungroup") else { return }
        guard let path = canvas.nodes.indexPath(of: id),
              case .group(let g)? = canvas.nodes.node(atPath: path) else { return }
        let groupNode = LayerNode.group(g)
        let children = g.children
        perform(MutateCommand(
            title: "Ungroup",
            doApply: { ctx in
                guard let p = ctx.canvas.nodes.indexPath(of: id) else { return }
                ctx.canvas.nodes.removeNode(atPath: p)
                for (k, child) in children.enumerated() {
                    var cp = p; cp[cp.count - 1] += k
                    ctx.canvas.nodes.insertNode(child, atPath: cp)
                }
                ctx.canvas.selectedLayerID = children.first?.id
            },
            doRevert: { ctx in
                for child in children { ctx.canvas.nodes.removeByID(child.id) }
                ctx.canvas.nodes.insertNode(groupNode, atPath: path)
                ctx.canvas.selectedLayerID = id
            }))
    }

    func moveNode(_ id: LayerID, intoGroup groupID: LayerID) {
        guard let canvas = activeCanvas else { return }
        guard id != groupID, !canvas.nodes.subtree(id, contains: groupID),
              let oldPath = canvas.nodes.indexPath(of: id),
              let node = canvas.nodes.node(atPath: oldPath) else { return }
        perform(MutateCommand(
            title: "Move Layer",
            doApply: { $0.canvas.nodes.moveNode(id, intoGroup: groupID) },
            doRevert: { ctx in ctx.canvas.nodes.removeByID(id); ctx.canvas.nodes.insertNode(node, atPath: oldPath) }))
    }

    func moveNode(_ id: LayerID, relativeTo targetID: LayerID, below: Bool) {
        guard let canvas = activeCanvas else { return }
        guard id != targetID, !canvas.nodes.subtree(id, contains: targetID),
              let oldPath = canvas.nodes.indexPath(of: id),
              let node = canvas.nodes.node(atPath: oldPath) else { return }
        perform(MutateCommand(
            title: "Move Layer",
            doApply: { $0.canvas.nodes.moveNode(id, relativeTo: targetID, below: below) },
            doRevert: { ctx in ctx.canvas.nodes.removeByID(id); ctx.canvas.nodes.insertNode(node, atPath: oldPath) }))
    }

    func setGroupOpacity(_ id: LayerID, _ value: Float) {
        guard let g = groupNode(id), g.opacity != value else { return }
        let old = g.opacity
        perform(MutateCommand(title: "Group Opacity",
            doApply: { $0.canvas.updateGroup(id) { $0.opacity = value } },
            doRevert: { $0.canvas.updateGroup(id) { $0.opacity = old } }))
    }
    func setGroupVisibility(_ id: LayerID, _ on: Bool) {
        guard let g = groupNode(id), g.isVisible != on else { return }
        perform(MutateCommand(title: on ? "Show Group" : "Hide Group",
            doApply: { $0.canvas.updateGroup(id) { $0.isVisible = on } },
            doRevert: { $0.canvas.updateGroup(id) { $0.isVisible = !on } }))
    }
    func setGroupBlend(_ id: LayerID, _ blend: BlendMode) {
        guard let g = groupNode(id), g.blend != blend else { return }
        let old = g.blend
        perform(MutateCommand(title: "Blend Mode",
            doApply: { $0.canvas.updateGroup(id) { $0.blend = blend } },
            doRevert: { $0.canvas.updateGroup(id) { $0.blend = old } }))
    }

    func setBlend(_ id: LayerID, _ blend: BlendMode) {
        if groupNode(id) != nil { setGroupBlend(id, blend) } else { setLayerBlend(id, blend) }
    }

    func renameGroup(_ id: LayerID, _ name: String) {
        guard let g = groupNode(id), g.name != name else { return }
        let old = g.name
        perform(MutateCommand(title: "Rename Group",
            doApply: { $0.canvas.updateGroup(id) { $0.name = name } },
            doRevert: { $0.canvas.updateGroup(id) { $0.name = old } }))
    }

    func renameNode(_ id: LayerID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if groupNode(id) != nil { renameGroup(id, trimmed) } else { renameLayer(id, trimmed) }
    }

    private func groupNode(_ id: LayerID) -> LayerGroup? {
        func find(_ nodes: [LayerNode]) -> LayerGroup? {
            for n in nodes {
                if case .group(let g) = n { if g.id == id { return g }; if let f = find(g.children) { return f } }
            }
            return nil
        }
        return find(activeCanvas?.nodes ?? [])
    }

    func group(_ id: LayerID) -> LayerGroup? { groupNode(id) }

    func commitGroupOpacity(_ id: LayerID, from old: Float) {
        guard let current = groupNode(id)?.opacity, current != old else { return }
        perform(MutateCommand(title: "Group Opacity",
            doApply: { $0.canvas.updateGroup(id) { $0.opacity = current } },
            doRevert: { $0.canvas.updateGroup(id) { $0.opacity = old } }))
    }

    // MARK: - Add / duplicate / remove

    private func nextName(_ base: String, in canvas: Canvas) -> String {
        let prefix = base + " "
        let maxN = canvas.nodes.allNames().compactMap { name -> Int? in
            name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count)) : nil
        }.max() ?? 0
        return "\(base) \(maxN + 1)"
    }

    func addLayer(name: String? = nil) {
        guard let canvas = requireCanvas("Add Layer") else { return }
        let layer = Layer(name: name ?? nextName("Layer", in: canvas))
        let previousSelection = canvas.selectedLayerID

        perform(MutateCommand(
            title: "Add Layer",
            doApply: { ctx in
                ctx.canvas.nodes.append(.layer(layer))
                ctx.canvas.selectedLayerID = layer.id
                _ = ctx.render.resources.store(for: .layer(layer.id), canvas: ctx.canvas)
            },
            doRevert: { ctx in
                ctx.render.resources.drop(.layer(layer.id))
                ctx.canvas.nodes.removeByID(layer.id)
                ctx.canvas.selectedLayerID = previousSelection
            }))
        selection = [layer.id]
    }

    func duplicateLayer(_ id: LayerID) {
        guard let canvas = requireCanvas("Duplicate Layer") else { return }
        guard let src = canvas.layer(id),
              let srcIndex = canvas.nodes.firstTopLevelIndex(of: id) else { return }
        let copy = Layer(name: src.name + " copy", isVisible: src.isVisible,
                         opacity: src.opacity, blend: src.blend)
        let snapshot = LayerSnapshot.capture(.layer(id), canvas: canvas,
                                             render: render, tileSize: config.tileSize)
        perform(DuplicateLayerCommand(newLayer: copy, index: srcIndex + 1,
                                      snapshot: snapshot, previousSelection: canvas.selectedLayerID))
        selection = [copy.id]
    }

    func removeLayer(_ id: LayerID) {
        guard let canvas = requireCanvas("Delete Layer") else { return }
        guard let index = canvas.nodes.firstTopLevelIndex(of: id),
              let layer = canvas.layer(id) else { return }
        let snapshot = LayerSnapshot.capture(.layer(id), canvas: canvas,
                                             render: render, tileSize: config.tileSize)
        perform(RemoveLayerCommand(layer: layer, index: index,
                                   snapshot: snapshot, previousSelection: canvas.selectedLayerID))
        reconcileSelection()
    }

    // MARK: - Merge

    var canMergeDown: Bool { activeCanvas?.selectedLayerID.map { canMergeDown($0) } ?? false }

    func canMergeDown(_ id: LayerID) -> Bool {
        guard let canvas = activeCanvas,
              let i = canvas.nodes.firstTopLevelIndex(of: id), i >= 1 else { return false }
        if case .layer = canvas.nodes[i], case .layer = canvas.nodes[i - 1] { return true }
        return false
    }

    func mergeDown() {
        guard let canvas = requireCanvas("Merge Down") else { return }
        guard let sel = canvas.selectedLayerID,
              let topIdx = canvas.nodes.firstTopLevelIndex(of: sel), topIdx >= 1,
              case .layer(let top) = canvas.nodes[topIdx],
              case .layer(let bottom) = canvas.nodes[topIdx - 1]
        else { notices.post("Select a layer with another layer directly below it", .warning); return }

        let tile = config.tileSize
        let topSnap = LayerSnapshot.capture(.layer(top.id), canvas: canvas, render: render, tileSize: tile)
        let bottomSnap = LayerSnapshot.capture(.layer(bottom.id), canvas: canvas, render: render, tileSize: tile)

        let fmt = canvas.colorMode.mtlPixelFormat
        guard let temp = render.acquireCompositeTemp(width: canvas.width, height: canvas.height, format: fmt) else {
            notices.post("Couldn’t allocate merge buffer", .error); return
        }
        var iso = canvas
        var bottomNormal = bottom; bottomNormal.blend = .normal
        iso.nodes = [.layer(bottomNormal), .layer(top)]
        Compositor.composite(iso, into: temp, ctx: render)
        let mergedSnap = LayerSnapshot.capture(texture: temp, tileSize: tile)
        render.releaseCompositeTemp(temp)

        perform(MergeDownCommand(top: top, topIndex: topIdx, bottomID: bottom.id,
                                 bottomName: bottom.name, bottomBlend: bottom.blend, bottomOpacity: bottom.opacity,
                                 topSnapshot: topSnap, bottomSnapshot: bottomSnap, mergedSnapshot: mergedSnap,
                                 previousSelection: sel))
        selection = [bottom.id]
    }

    // MARK: - Metadata edits (MutateCommand)

    func setLayerOpacity(_ id: LayerID, _ value: Float) {
        editLayer(id, title: "Layer Opacity", get: { $0.opacity }, set: { $0.opacity = value }, newIfChanged: value)
    }
    func setLayerVisibility(_ id: LayerID, _ on: Bool) {
        editLayer(id, title: on ? "Show Layer" : "Hide Layer", get: { $0.isVisible }, set: { $0.isVisible = on }, newIfChanged: on)
    }
    func renameLayer(_ id: LayerID, _ name: String) {
        editLayer(id, title: "Rename Layer", get: { $0.name }, set: { $0.name = name }, newIfChanged: name)
    }
    func setLayerBlend(_ id: LayerID, _ blend: BlendMode) {
        editLayer(id, title: "Blend Mode", get: { $0.blend }, set: { $0.blend = blend }, newIfChanged: blend)
    }

    func moveLayer(_ id: LayerID, to index: Int) {
        guard let from = activeCanvas?.nodes.firstTopLevelIndex(of: id) else { return }
        perform(MutateCommand(
            title: "Reorder Layer",
            doApply: { $0.canvas.nodes.move(nodeID: id, to: index) },
            doRevert: { $0.canvas.nodes.move(nodeID: id, to: from) }))
    }

    // MARK: - Generic single-property edit

    private func editLayer<Value: Equatable>(_ id: LayerID, title: String,
                                             get: (Layer) -> Value,
                                             set: @escaping (inout Layer) -> Void,
                                             newIfChanged: Value) {
        guard let current = activeCanvas?.layer(id), get(current) != newIfChanged else { return }
        let old = current
        perform(MutateCommand(
            title: title,
            doApply: { ctx in ctx.canvas.updateLayer(id) { set(&$0) } },
            doRevert: { ctx in ctx.canvas.updateLayer(id) { $0 = old } }))
    }
}
