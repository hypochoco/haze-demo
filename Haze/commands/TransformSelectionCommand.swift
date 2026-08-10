//
//  TransformSelectionCommand.swift
//  Haze — commands
//

struct TransformSelectionCommand: Command {
    let target: PixelTarget
    let diff: PixelDiff
    let maskBefore: MaskSnapshot
    let maskAfter: MaskSnapshot

    var title: String { "Transform Selection" }
    var byteCost: Int { diff.byteCount + maskBefore.byteCount + maskAfter.byteCount }
    var affectedLayers: [LayerID] { target.layerID.map { [$0] } ?? [] }

    func apply(_ ctx: CommandContext) {
        diff.restoreAfter(to: target, render: ctx.render, canvas: ctx.canvas)
        maskAfter.restore(ctx)
    }

    func revert(_ ctx: CommandContext) {
        diff.restoreBefore(to: target, render: ctx.render, canvas: ctx.canvas)
        maskBefore.restore(ctx)
    }
}
