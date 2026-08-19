//
//  LayerThumbnailView.swift
//  Haze — views/panels
//

import SwiftUI

@MainActor
struct LayerThumbnailView: View {
    let store: Store
    let layerID: LayerID
    @ObservedObject private var versions: ContentVersions
    @ObservedObject private var thumbs: LayerThumbnailCache

    init(store: Store, layerID: LayerID) {
        self.store = store
        self.layerID = layerID
        self.versions = store.contentVersions
        self.thumbs = store.thumbnailCache
    }

    var body: some View {
        let version = versions.version(layerID)
        let image = store.activeCanvas.flatMap {
            thumbs.image(for: .layer(layerID), version: version, canvas: $0, render: store.render)
        }
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor))
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4))
        }
        .frame(width: 32, height: 32)
    }
}
