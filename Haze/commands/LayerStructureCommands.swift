//
//  LayerStructureCommands.swift
//  Haze — commands
//

struct RemoveLayerCommand: Command {
    let layer: Layer
    let index: Int
    let snapshot: LayerSnapshot
    let previousSelection: LayerID?

    var title: String { "Delete Layer" }
    var byteCost: Int { snapshot.byteCount }
    var affectedLayers: [LayerID] { [layer.id] }

    func apply(_ ctx: CommandContext) {
        ctx.canvas.nodes.removeByID(layer.id)
        ctx.render.resources.drop(.layer(layer.id))
        if ctx.canvas.selectedLayerID == layer.id {
            ctx.canvas.selectedLayerID = ctx.canvas.nodes.leaves.last?.id
        }
    }

    func revert(_ ctx: CommandContext) {
        let dest = min(index, ctx.canvas.nodes.count)
        ctx.canvas.nodes.insert(.layer(layer), at: dest)
        _ = ctx.render.resources.store(for: .layer(layer.id), canvas: ctx.canvas)
        snapshot.restore(.layer(layer.id), render: ctx.render, canvas: ctx.canvas)
        ctx.canvas.selectedLayerID = previousSelection ?? layer.id
    }
}

struct DuplicateLayerCommand: Command {
    let newLayer: Layer
    let index: Int
    let snapshot: LayerSnapshot
    let previousSelection: LayerID?

    var title: String { "Duplicate Layer" }
    var byteCost: Int { snapshot.byteCount }
    var affectedLayers: [LayerID] { [newLayer.id] }

    func apply(_ ctx: CommandContext) {
        let dest = min(index, ctx.canvas.nodes.count)
        ctx.canvas.nodes.insert(.layer(newLayer), at: dest)
        _ = ctx.render.resources.store(for: .layer(newLayer.id), canvas: ctx.canvas)
        snapshot.restore(.layer(newLayer.id), render: ctx.render, canvas: ctx.canvas)
        ctx.canvas.selectedLayerID = newLayer.id
    }

    func revert(_ ctx: CommandContext) {
        ctx.canvas.nodes.removeByID(newLayer.id)
        ctx.render.resources.drop(.layer(newLayer.id))
        ctx.canvas.selectedLayerID = previousSelection
    }
}

struct MergeDownCommand: Command {
    let top: Layer
    let topIndex: Int
    let bottomID: LayerID
    let bottomName: String
    let bottomBlend: BlendMode
    let bottomOpacity: Float
    let topSnapshot: LayerSnapshot
    let bottomSnapshot: LayerSnapshot
    let mergedSnapshot: LayerSnapshot
    let previousSelection: LayerID?

    var title: String { "Merge Down" }
    var byteCost: Int { topSnapshot.byteCount + bottomSnapshot.byteCount + mergedSnapshot.byteCount }
    var affectedLayers: [LayerID] { [bottomID, top.id] }

    func apply(_ ctx: CommandContext) {
        ctx.canvas.nodes.removeByID(top.id)
        ctx.render.resources.drop(.layer(top.id))
        ctx.canvas.nodes.updateLayer(bottomID) { $0.blend = .normal; $0.opacity = 1 }
        replacePixels(mergedSnapshot, of: bottomID, ctx)
        ctx.canvas.selectedLayerID = bottomID
    }

    func revert(_ ctx: CommandContext) {
        replacePixels(bottomSnapshot, of: bottomID, ctx)
        ctx.canvas.nodes.updateLayer(bottomID) {
            $0.name = bottomName; $0.blend = bottomBlend; $0.opacity = bottomOpacity
        }
        let dest = min(topIndex, ctx.canvas.nodes.count)
        ctx.canvas.nodes.insert(.layer(top), at: dest)
        _ = ctx.render.resources.store(for: .layer(top.id), canvas: ctx.canvas)
        topSnapshot.restore(.layer(top.id), render: ctx.render, canvas: ctx.canvas)
        ctx.canvas.selectedLayerID = previousSelection
    }

    private func replacePixels(_ snap: LayerSnapshot, of id: LayerID, _ ctx: CommandContext) {
        ctx.render.resources.store(for: .layer(id), canvas: ctx.canvas)?
            .reallocateBlank(toWidth: ctx.canvas.width, toHeight: ctx.canvas.height)
        snap.restore(.layer(id), render: ctx.render, canvas: ctx.canvas)
    }
}

struct BakeToLayerCommand: Command {
    let title: String
    let oldNodes: [LayerNode]
    let newNodes: [LayerNode]
    let newLeafID: LayerID
    let mergedSnapshot: LayerSnapshot
    let removed: [(id: LayerID, snap: LayerSnapshot)]
    let previousSelection: LayerID?

    var byteCost: Int { mergedSnapshot.byteCount + removed.reduce(0) { $0 + $1.snap.byteCount } }
    var affectedLayers: [LayerID] { [newLeafID] + removed.map(\.id) }

    func apply(_ ctx: CommandContext) {
        for r in removed { ctx.render.resources.drop(.layer(r.id)) }
        ctx.canvas.nodes = newNodes
        _ = ctx.render.resources.store(for: .layer(newLeafID), canvas: ctx.canvas)
        mergedSnapshot.restore(.layer(newLeafID), render: ctx.render, canvas: ctx.canvas)
        ctx.canvas.selectedLayerID = newLeafID
    }

    func revert(_ ctx: CommandContext) {
        ctx.render.resources.drop(.layer(newLeafID))
        ctx.canvas.nodes = oldNodes
        for r in removed {
            _ = ctx.render.resources.store(for: .layer(r.id), canvas: ctx.canvas)
            r.snap.restore(.layer(r.id), render: ctx.render, canvas: ctx.canvas)
        }
        ctx.canvas.selectedLayerID = previousSelection
    }
}
