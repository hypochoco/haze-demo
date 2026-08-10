//
//  CanvasImage.swift
//  Haze — io
//

import Foundation

enum SectionDivider: Equatable {
    case none
    case bounding
    case open
    case closed

    var isGroupHeader: Bool { self == .open || self == .closed }
}

struct LayerImage {
    var name: String
    var isVisible: Bool
    var opacity: Float
    var blendMode: BlendMode
    var pixels: [UInt8]
    var divider: SectionDivider = .none
    var maskPixels: [UInt8]? = nil
    var maskEnabled: Bool = true
}

struct CanvasImage {
    var fileName: String
    var width: Int
    var height: Int
    var layers: [LayerImage]
    var depth: PixelDepth = .eight
    var space: WorkingSpace = .sRGB
    var dpi: Double = 72
    var flattenedOverride: [UInt8]? = nil

    var pixelCount: Int { width * height }
    var bytesPerSample: Int { depth == .eight ? 1 : 2 }

    func mergedForEncoding() -> [UInt8] {
        if let o = flattenedOverride, o.count == pixelCount * 4 * bytesPerSample { return o }
        return flattenedRGBA()
    }

    func strippingMasks() -> (image: CanvasImage, skipped: Int) {
        let skipped = layers.reduce(0) { $0 + ($1.maskPixels != nil ? 1 : 0) }
        guard skipped > 0 else { return (self, 0) }
        var copy = self
        for i in copy.layers.indices {
            copy.layers[i].maskPixels = nil
            copy.layers[i].maskEnabled = true
        }
        return (copy, skipped)
    }

    func convertedToDemoFormat() -> (image: CanvasImage, depthConverted: Bool, spaceConverted: Bool) {
        let depthConverted = depth == .sixteen
        let spaceConverted = space == .displayP3
        guard depthConverted || spaceConverted else { return (self, false, false) }
        var img = self

        if depthConverted {
            for i in img.layers.indices where !img.layers[i].pixels.isEmpty {
                img.layers[i].pixels = PixelConversion.straightRGBA16ToStraightRGBA8(img.layers[i].pixels)
            }
            if let o = img.flattenedOverride { img.flattenedOverride = PixelConversion.straightRGBA16ToStraightRGBA8(o) }
            img.depth = .eight
        }
        if spaceConverted {
            for i in img.layers.indices where !img.layers[i].pixels.isEmpty {
                img.layers[i].pixels = PixelConversion.remapStraightRGBA8(img.layers[i].pixels, from: .displayP3, to: .sRGB)
            }
            if let o = img.flattenedOverride { img.flattenedOverride = PixelConversion.remapStraightRGBA8(o, from: .displayP3, to: .sRGB) }
            img.space = .sRGB
        }
        return (img, depthConverted, spaceConverted)
    }

    func flattenedRGBA() -> [UInt8] {
        let count = pixelCount
        if let override = flattenedOverride, override.count == count * 4 { return override }
        var out = [Float](repeating: 0, count: count * 4)

        for layer in layers where layer.divider == .none && layer.isVisible && layer.opacity > 0 {
            let px = layer.pixels
            guard px.count == count * 4 else { continue }
            let layerOpacity = layer.opacity
            for i in 0..<count {
                let o = i * 4
                let sa = (Float(px[o + 3]) / 255) * layerOpacity
                if sa <= 0 { continue }
                let sr = Float(px[o + 0]) / 255
                let sg = Float(px[o + 1]) / 255
                let sb = Float(px[o + 2]) / 255
                let da = out[o + 3]
                let outA = sa + da * (1 - sa)
                if outA <= 0 { continue }
                out[o + 0] = (sr * sa + out[o + 0] * da * (1 - sa)) / outA
                out[o + 1] = (sg * sa + out[o + 1] * da * (1 - sa)) / outA
                out[o + 2] = (sb * sa + out[o + 2] * da * (1 - sa)) / outA
                out[o + 3] = outA
            }
        }

        var bytes = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<(count * 4) {
            bytes[i] = UInt8(max(0, min(255, (out[i] * 255).rounded())))
        }
        return bytes
    }
}

enum CodecError: Error, CustomStringConvertible {
    case malformed(String)
    case unsupported(String)
    case io(String)

    var description: String {
        switch self {
        case .malformed(let m): return "Malformed file: \(m)"
        case .unsupported(let m): return "Unsupported feature: \(m)"
        case .io(let m): return "I/O error: \(m)"
        }
    }
}

protocol ImageDocumentCodec {
    static var fileExtensions: [String] { get }
    func encode(_ image: CanvasImage) throws -> Data
    func decode(_ data: Data) throws -> CanvasImage
}
