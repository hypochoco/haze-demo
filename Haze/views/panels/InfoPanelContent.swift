//
//  InfoPanelContent.swift
//  Haze — views/panels
//

import SwiftUI
import Foundation

struct InfoPanelContent: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let canvas = store.activeCanvas {
                Text("Canvas").font(.headline)
                Text("\(canvas.width) × \(canvas.height) px").foregroundStyle(.secondary)
                Text("Resolution: \(Int(canvas.dpi.rounded())) DPI").foregroundStyle(.secondary)
                Text("Layers: \(canvas.layers.count)").foregroundStyle(.secondary)
                Text("Uncompressed: \(uncompressedSize(canvas))").foregroundStyle(.secondary)
            } else {
                Text("No canvas").font(.headline)
                Text("Create or open a canvas to begin.").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(width: 200, alignment: .leading)
    }

    private func uncompressedSize(_ canvas: Canvas) -> String {
        let bytes = canvas.width * canvas.height * canvas.colorMode.bytesPerPixel * max(1, canvas.layers.count)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
