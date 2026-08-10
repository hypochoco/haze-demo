//
//  ImageFormat.swift
//  Haze — io
//

import Foundation
import UniformTypeIdentifiers

struct ImageExportOptions {
    var jpegQuality: Double = 0.9
}

protocol ImageFormat {
    static var displayName: String { get }
    static var fileExtensions: [String] { get }
    static var utType: UTType { get }
    static var canWrite: Bool { get }
    static var canRead: Bool { get }
    static var supportsLayers: Bool { get }

    static func encode(_ canvas: Canvas, render: RenderContext, fileName: String,
                       options: ImageExportOptions) throws -> Data
    static func decode(_ data: Data, fileName: String) throws -> CanvasImage
}

extension ImageFormat {
    static func handles(ext: String) -> Bool { fileExtensions.contains(ext.lowercased()) }
}

enum DocumentFormatRegistry {
    static let formats: [ImageFormat.Type] = [PSDFormat.self, PNGFormat.self, JPEGFormat.self]

    static var writable: [ImageFormat.Type] { formats.filter { $0.canWrite } }
    static var readable: [ImageFormat.Type] { formats.filter { $0.canRead } }
    static var readableTypes: [UTType] { readable.map { $0.utType } }
    static var writableTypes: [UTType] { writable.map { $0.utType } }

    static func format(forExt ext: String) -> ImageFormat.Type? {
        formats.first { $0.handles(ext: ext) }
    }
}

// MARK: - Shared flatten (composite read-back) for flat raster formats

enum ImageExport {
    static func flattenedComposite(_ canvas: Canvas, render: RenderContext) -> [UInt8] {
        let w = canvas.width, h = canvas.height
        guard let target = render.compositeTexture(width: w, height: h,
                                                   format: canvas.colorMode.mtlPixelFormat) else {
            return []
        }
        Compositor.composite(canvas, into: target, ctx: render)
        render.flush()
        let raw = RenderContext.readBytes(from: target)
        return PixelConversion.premultipliedBGRAToStraightRGBA(raw)
    }
}

// MARK: - PSD head (delegates to the existing PSD codec — layered, native working format)

enum PSDFormat: ImageFormat {
    static let displayName = "Photoshop (PSD)"
    static let fileExtensions = ["psd"]
    static let utType = UTType(filenameExtension: "psd") ?? .data
    static let canWrite = true
    static let canRead = true
    static let supportsLayers = true

    static func encode(_ canvas: Canvas, render: RenderContext, fileName: String,
                       options: ImageExportOptions) throws -> Data {
        try PSDExport.encode(canvas, render: render, fileName: fileName)
    }

    static func decode(_ data: Data, fileName: String) throws -> CanvasImage {
        var image = try PSDCodec().decode(data)
        image.fileName = fileName
        return image
    }
}
