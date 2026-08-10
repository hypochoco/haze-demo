//
//  MutateCommand.swift
//  Haze — commands
//

struct MutateCommand: Command {
    let title: String
    let doApply: (CommandContext) -> Void
    let doRevert: (CommandContext) -> Void

    func apply(_ ctx: CommandContext) { doApply(ctx) }
    func revert(_ ctx: CommandContext) { doRevert(ctx) }
}
