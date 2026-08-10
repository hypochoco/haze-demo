//
//  PixelEditCommand.swift
//  Haze — commands
//

struct PixelEditCommand: Command {
    let title: String
    let target: PixelTarget
    let diff: PixelDiff

    var byteCost: Int { diff.byteCount }
    var affectedLayers: [LayerID] { target.layerID.map { [$0] } ?? [] }

    func apply(_ ctx: CommandContext) {
        diff.restoreAfter(to: target, render: ctx.render, canvas: ctx.canvas)
    }

    func revert(_ ctx: CommandContext) {
        diff.restoreBefore(to: target, render: ctx.render, canvas: ctx.canvas)
    }
}
