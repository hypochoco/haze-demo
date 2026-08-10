//
//  CoordinateSpace.swift
//  Haze — input
//

import simd

struct CanvasPoint: Equatable {
    var x: Float
    var y: Float
    init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
    init(_ v: SIMD2<Float>) { self.x = v.x; self.y = v.y }
    var simd: SIMD2<Float> { [x, y] }
}

struct ViewPoint: Equatable {
    var x: Float
    var y: Float
    init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
    var simd: SIMD2<Float> { [x, y] }
}
