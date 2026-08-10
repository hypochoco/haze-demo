//
//  Checkerboard.swift
//  Haze — views/shared
//

import SwiftUI

struct Checkerboard: View {
    var square: CGFloat = 6
    var light = Color(white: 0.95)
    var dark = Color(white: 0.80)

    var body: some View {
        SwiftUI.Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let cols = Int(ceil(size.width / square)), rows = Int(ceil(size.height / square))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square,
                                         width: square, height: square)), with: .color(dark))
                }
            }
        }
    }
}
