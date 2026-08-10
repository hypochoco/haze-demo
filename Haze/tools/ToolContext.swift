//
//  Tool.swift
//  Haze — tools
//

import Metal

@MainActor
protocol Tool {
    func handle(_ input: ToolInput, _ ctx: ToolContext)
}

@MainActor
struct ToolContext {
    let render: RenderContext
    let canvas: Canvas
    let target: PixelTarget
    let brush: BrushSettings
    var tileSize: Int = 256
    var record: (Command) -> Void = { _ in }
    var selectionMask: MTLTexture? = nil
    var erase: Bool = false
}
