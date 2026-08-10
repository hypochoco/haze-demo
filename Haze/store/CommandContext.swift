//
//  CommandContext.swift
//  Haze — store
//

@MainActor
final class CommandContext {
    var canvas: Canvas
    let render: RenderContext
    let config: Config

    init(canvas: Canvas, render: RenderContext, config: Config) {
        self.canvas = canvas
        self.render = render
        self.config = config
    }
}
