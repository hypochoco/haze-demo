//
//  Store+ForegroundColor.swift
//  Haze — store
//

import simd

extension Store {
    var foregroundColor: SIMD4<Float> {
        get { editor[paint: .brush].color }
        set {
            var e = editor
            for tool in ToolKind.allCases where tool.isPaint { e[paint: tool].color = newValue }
            editor = e
        }
    }
}
