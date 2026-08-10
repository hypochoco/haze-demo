//
//  BrushPreviewCache.swift
//  Haze — views/panels
//

import SwiftUI
import Combine
import CoreGraphics
import simd

@MainActor
final class BrushPreviewCache: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private var icons: [String: CGImage] = [:]
    private var tipIcons: [String: CGImage] = [:]
    private var stripKey: String?
    private var stripImage: CGImage?

    // MARK: - Preset icon (single centred dab, colour-agnostic)

    func icon(for settings: BrushSettings, render: RenderContext, dim: Int = 52) -> CGImage? {
        let key = "\(dim)|\(settings.size)|\(settings.hardness)|\(settings.flow)"
        if let img = icons[key] { return img }
        let maxR = Float(dim) / 2 - 2
        let r = min(maxR, max(Float(dim) * 0.34, sqrt(settings.size) * (maxR / sqrt(300)) * 1.3))
        let dab = Dab(center: [Float(dim) / 2, Float(dim) / 2], radius: r, flow: settings.flow)
        let img = render.renderBrushSample(width: dim, height: dim, dabs: [dab],
                                           color: [0, 0, 0, 1], hardness: settings.hardness, opacity: 1)
        if let img { icons[key] = img }
        return img
    }

    // MARK: - Tip shape icons

    func tipIcon(for brush: BrushSettings, render: RenderContext, dim: Int = 56) -> CGImage? {
        let key = "tip|\(dim)|\(brush.tipID?.uuidString ?? "round")|\(brush.roundness)|\(brush.angle)|\(brush.hardness)"
        if let img = tipIcons[key] { return img }
        let r = Float(dim) / 2 - 3
        let dab = Dab(center: [Float(dim) / 2, Float(dim) / 2], radius: r, flow: 1, angle: brush.angleRadians)
        let img = render.renderBrushSample(width: dim, height: dim, dabs: [dab],
                                           color: [0, 0, 0, 1], hardness: brush.hardness, opacity: 1,
                                           tipID: brush.tipID, roundness: brush.roundness)
        if let img { tipIcons[key] = img }
        return img
    }

    func tipThumb(for tipID: UUID?, render: RenderContext, dim: Int = 44) -> CGImage? {
        let key = "thumb|\(dim)|\(tipID?.uuidString ?? "round")"
        if let img = tipIcons[key] { return img }
        let r = Float(dim) / 2 - 3
        let dab = Dab(center: [Float(dim) / 2, Float(dim) / 2], radius: r, flow: 1)
        let img = render.renderBrushSample(width: dim, height: dim, dabs: [dab],
                                           color: [0, 0, 0, 1], hardness: 0.9, opacity: 1,
                                           tipID: tipID, roundness: 1)
        if let img { tipIcons[key] = img }
        return img
    }

    // MARK: - Live current-brush stroke strip

    func strokeStrip(for brush: BrushSettings, render: RenderContext,
                     width: Int = 220, height: Int = 46) -> CGImage? {
        let key = brushKey(brush, width: width, height: height)
        if key == stripKey { return stripImage }
        let dabs = Self.strokeDabs(brush, width: width, height: height)
        let img = render.renderBrushSample(width: width, height: height, dabs: dabs,
                                           color: brush.color, hardness: brush.hardness, opacity: brush.opacity,
                                           tipID: brush.tipID, roundness: brush.roundness)
        stripKey = key; stripImage = img
        return img
    }

    private func brushKey(_ b: BrushSettings, width: Int, height: Int) -> String {
        "\(width)x\(height)|\(b.size)|\(b.hardness)|\(b.spacing)|\(b.flow)|\(b.opacity)|\(b.color.x),\(b.color.y),\(b.color.z),\(b.color.w)"
        + "|\(b.tipID?.uuidString ?? "r")|\(b.angle)|\(b.roundness)|\(b.scatter)|\(b.sizeJitter)|\(b.angleJitter)|\(b.angleFollowsDirection)"
    }

    private static func strokeDabs(_ b: BrushSettings, width: Int, height: Int) -> [Dab] {
        let cappedR = min(b.radius, Float(height) / 2 - 3)
        let cappedR2 = max(1.5, cappedR)
        let spacingPx = max(1, b.spacing * cappedR2 * 2)
        var gen = DabGenerator(radius: cappedR2, spacing: spacingPx, flow: b.flow,
                               angle: b.angleRadians, angleJitter: b.angleJitter,
                               sizeJitter: b.sizeJitter, scatter: b.scatter,
                               angleFollowsDirection: b.angleFollowsDirection)
        let margin = cappedR2 + 2
        let amp = (Float(height) / 2 - margin) * 0.85
        let n = 48
        var dabs: [Dab] = []
        for i in 0...n {
            let t = Float(i) / Float(n)
            let x = margin + t * (Float(width) - 2 * margin)
            let y = Float(height) / 2 + sin(t * .pi * 2) * amp
            dabs += (i == 0 ? gen.begin([x, y]) : gen.extend(to: [x, y]))
        }
        return dabs
    }
}
