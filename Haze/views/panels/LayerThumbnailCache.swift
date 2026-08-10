//
//  LayerThumbnailCache.swift
//  Haze — views/panels
//

import SwiftUI
import Combine
import CoreGraphics

@MainActor
final class LayerThumbnailCache: ObservableObject {
    private var cache: [PixelTarget: (version: Int, image: CGImage)] = [:]
    private var inFlight: [PixelTarget: Int] = [:]
    @Published private var tick = 0

    func image(for target: PixelTarget, version: Int, canvas: Canvas, render: RenderContext) -> CGImage? {
        if let cached = cache[target], cached.version == version { return cached.image }
        if inFlight[target] != version {
            inFlight[target] = version
            render.renderThumbnail(target, canvas: canvas, maxDim: 44) { [weak self] image in
                MainActor.assumeIsolated {
                    if let image { self?.deliver(target: target, version: version, image: image) }
                }
            }
        }
        return cache[target]?.image
    }

    func deliver(target: PixelTarget, version: Int, image: CGImage) {
        guard inFlight[target] == version else { return }
        inFlight[target] = nil
        cache[target] = (version, image)
        tick &+= 1
    }

    // MARK: - Testing seam (layer targets)
    func requestVersion(_ id: LayerID, _ version: Int) { inFlight[.layer(id)] = version }
    func currentVersion(_ id: LayerID) -> Int? { cache[.layer(id)]?.version }
    func deliver(id: LayerID, version: Int, image: CGImage) { deliver(target: .layer(id), version: version, image: image) }
}
