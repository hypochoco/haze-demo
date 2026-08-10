//
//  ToolInput.swift
//  Haze — input
//

struct ToolInput {
    enum Phase { case begin, moved, ended }
    var point: CanvasPoint
    var pressure: Float
    var phase: Phase
}
