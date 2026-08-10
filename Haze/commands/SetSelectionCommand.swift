//
//  SetSelectionCommand.swift
//  Haze — commands
//

struct SetSelectionCommand: Command {
    let title: String
    let before: MaskSnapshot
    let after: MaskSnapshot

    var byteCost: Int { before.byteCount + after.byteCount }

    func apply(_ ctx: CommandContext) { after.restore(ctx) }
    func revert(_ ctx: CommandContext) { before.restore(ctx) }
}
