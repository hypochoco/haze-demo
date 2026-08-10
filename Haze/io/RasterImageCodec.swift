//
//  RasterImageCodec.swift
//  Haze — io
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum RasterImageCodec {

    // MARK: Encode

    static func encode(straight: [UInt8], width: Int, height: Int, depth: PixelDepth,
                       space: WorkingSpace, dpi: Double, utType: UTType,
                       hasAlpha: Bool, quality: Double?) -> Data? {
        guard width > 0, height > 0 else { return nil }
        let sixteen = depth == .sixteen
        let bps = sixteen ? 16 : 8
        let bytesPerPixel = (bps / 8) * 4
        guard straight.count == width * height * bytesPerPixel else { return nil }

        let pixels = hasAlpha ? straight : Self.matteOntoWhite(straight, depth: depth)

        var bitmapInfo = CGBitmapInfo(rawValue: (hasAlpha ? CGImageAlphaInfo.last
                                                          : CGImageAlphaInfo.noneSkipLast).rawValue)
        if sixteen { bitmapInfo.insert(.byteOrder16Little) }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height,
                               bitsPerComponent: bps, bitsPerPixel: bps * 4,
                               bytesPerRow: width * bytesPerPixel,
                               space: space.cgColorSpace, bitmapInfo: bitmapInfo,
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, utType.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private static func matteOntoWhite(_ src: [UInt8], depth: PixelDepth) -> [UInt8] {
        if depth == .sixteen {
            var out = src
            let n = out.count / 8
            for p in 0..<n {
                let o = p * 8
                let a = Int(out[o + 6]) | (Int(out[o + 7]) << 8)
                if a == 65535 { continue }
                for c in 0..<3 {
                    let s = o + c * 2
                    let v = Int(out[s]) | (Int(out[s + 1]) << 8)
                    let m = (v * a + 65535 * (65535 - a)) / 65535
                    out[s] = UInt8(m & 0xff); out[s + 1] = UInt8((m >> 8) & 0xff)
                }
                out[o + 6] = 0xff; out[o + 7] = 0xff
            }
            return out
        } else {
            var out = src
            let n = out.count / 4
            for p in 0..<n {
                let o = p * 4
                let a = Int(out[o + 3])
                if a == 255 { continue }
                for c in 0..<3 { out[o + c] = UInt8((Int(out[o + c]) * a + 255 * (255 - a)) / 255) }
                out[o + 3] = 255
            }
            return out
        }
    }

    // MARK: Decode

    struct Decoded {
        var pixels: [UInt8]
        var width: Int
        var height: Int
        var dpi: Double
        var space: WorkingSpace
    }

    static func decode(_ data: Data) -> Decoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }

        let isP3 = (cg.colorSpace?.name).map { ($0 as String).localizedCaseInsensitiveContains("P3") } ?? false
        let space: WorkingSpace = isP3 ? .displayP3 : .sRGB

        var premul = [UInt8](repeating: 0, count: w * h * 4)
        let ok = premul.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space.cgColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        var straight = premul
        let n = w * h
        for p in 0..<n {
            let o = p * 4
            let a = Int(straight[o + 3])
            if a == 0 { straight[o] = 0; straight[o + 1] = 0; straight[o + 2] = 0; continue }
            if a == 255 { continue }
            for c in 0..<3 { straight[o + c] = UInt8(min(255, Int(straight[o + c]) * 255 / a)) }
        }

        var dpi: Double = 72
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let d = props[kCGImagePropertyDPIWidth] as? Double, d > 0 { dpi = d }

        return Decoded(pixels: straight, width: w, height: h, dpi: dpi, space: space)
    }

    static func canvasImage(_ d: Decoded, fileName: String) -> CanvasImage {
        CanvasImage(fileName: fileName, width: d.width, height: d.height,
                    layers: [LayerImage(name: fileName, isVisible: true, opacity: 1,
                                        blendMode: .normal, pixels: d.pixels)],
                    depth: .eight, space: d.space, dpi: d.dpi)
    }
}

// MARK: - PNG head (lossless, alpha + 8/16-bit)

enum PNGFormat: ImageFormat {
    static let displayName = "PNG image"
    static let fileExtensions = ["png"]
    static let utType = UTType.png
    static let canWrite = true
    static let canRead = true
    static let supportsLayers = false

    static func encode(_ canvas: Canvas, render: RenderContext, fileName: String,
                       options: ImageExportOptions) throws -> Data {
        let straight = ImageExport.flattenedComposite(canvas, render: render)
        guard let data = RasterImageCodec.encode(straight: straight, width: canvas.width, height: canvas.height,
                                                 depth: canvas.colorMode.depth, space: canvas.colorMode.space,
                                                 dpi: canvas.dpi, utType: utType, hasAlpha: true, quality: nil)
        else { throw CodecError.io("PNG encode failed") }
        return data
    }

    static func decode(_ data: Data, fileName: String) throws -> CanvasImage {
        guard let d = RasterImageCodec.decode(data) else { throw CodecError.malformed("not a readable PNG") }
        return RasterImageCodec.canvasImage(d, fileName: fileName)
    }
}

// MARK: - JPEG head (lossy, 8-bit, no alpha → matted onto white)

enum JPEGFormat: ImageFormat {
    static let displayName = "JPEG image"
    static let fileExtensions = ["jpg", "jpeg"]
    static let utType = UTType.jpeg
    static let canWrite = true
    static let canRead = true
    static let supportsLayers = false

    static func encode(_ canvas: Canvas, render: RenderContext, fileName: String,
                       options: ImageExportOptions) throws -> Data {
        let straight = ImageExport.flattenedComposite(canvas, render: render)
        guard let data = RasterImageCodec.encode(straight: straight, width: canvas.width, height: canvas.height,
                                                 depth: canvas.colorMode.depth, space: canvas.colorMode.space,
                                                 dpi: canvas.dpi, utType: utType, hasAlpha: false,
                                                 quality: options.jpegQuality)
        else { throw CodecError.io("JPEG encode failed") }
        return data
    }

    static func decode(_ data: Data, fileName: String) throws -> CanvasImage {
        guard let d = RasterImageCodec.decode(data) else { throw CodecError.malformed("not a readable JPEG") }
        return RasterImageCodec.canvasImage(d, fileName: fileName)
    }
}
