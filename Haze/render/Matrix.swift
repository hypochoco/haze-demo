//
//  Matrix.swift
//  Haze — render
//

import simd

extension simd_float4x4 {
    static func imageOrthographic(width: Float, height: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = 2 / max(width, 1)
        m.columns.1.y = -2 / max(height, 1)
        m.columns.3.x = -1
        m.columns.3.y = 1
        return m
    }
}
