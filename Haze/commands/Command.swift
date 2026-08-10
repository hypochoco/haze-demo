//
//  Command.swift
//  Haze — commands
//

@MainActor
protocol Command {
    var title: String { get }
    func apply(_ ctx: CommandContext)
    func revert(_ ctx: CommandContext)
    var byteCost: Int { get }
    var affectedLayers: [LayerID] { get }
}

extension Command {
    var byteCost: Int { 0 }
    var affectedLayers: [LayerID] { [] }
}
