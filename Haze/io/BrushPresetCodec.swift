//
//  BrushPresetCodec.swift
//  Haze — io
//

import Foundation

struct BrushImportResult {
    var presets: [BrushPreset]
    var skipped: [String] = []
}

enum BrushPresetError: Error, LocalizedError {
    case unsupportedFormat(String)
    case notWritable(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let e): return "Unsupported brush format: .\(e)"
        case .notWritable(let n):       return "\(n) can’t be written"
        case .empty:                    return "Nothing to export"
        }
    }
}

protocol BrushPresetCodec {
    static var displayName: String { get }
    static var fileExtensions: [String] { get }
    static var canWrite: Bool { get }
    static func sniff(_ data: Data, ext: String) -> Bool
    static func decode(_ data: Data) throws -> BrushImportResult
    static func encode(_ presets: [BrushPreset]) throws -> Data
}

extension BrushPresetCodec {
    static func encode(_ presets: [BrushPreset]) throws -> Data {
        throw BrushPresetError.notWritable(displayName)
    }
}

enum BrushPresetIO {
    static let codecs: [BrushPresetCodec.Type] = [HazeBrushCodec.self]

    static var writable: [BrushPresetCodec.Type] { codecs.filter { $0.canWrite } }
    static var readableExtensions: [String] { codecs.flatMap { $0.fileExtensions } }

    static func codec(forExt ext: String, data: Data) throws -> BrushPresetCodec.Type {
        if let c = codecs.first(where: { $0.sniff(data, ext: ext.lowercased()) }) { return c }
        throw BrushPresetError.unsupportedFormat(ext)
    }

    static func importFile(at url: URL) throws -> BrushImportResult {
        let data = try Data(contentsOf: url)
        return try codec(forExt: url.pathExtension, data: data).decode(data)
    }

    static func exportFile(_ presets: [BrushPreset], to url: URL,
                           using codec: BrushPresetCodec.Type) throws {
        guard codec.canWrite else { throw BrushPresetError.notWritable(codec.displayName) }
        guard !presets.isEmpty else { throw BrushPresetError.empty }
        try codec.encode(presets).write(to: url, options: .atomic)
    }
}

// MARK: - Native format (.hazebrush) — full fidelity, reuses the library envelope.

enum HazeBrushCodec: BrushPresetCodec {
    static let displayName = "Haze Brushes"
    static let fileExtensions = ["hazebrush"]
    static let canWrite = true

    static func sniff(_ data: Data, ext: String) -> Bool {
        if fileExtensions.contains(ext) { return true }
        return (try? JSONDecoder().decode(BrushLibraryFile.self, from: data)) != nil
    }

    static func decode(_ data: Data) throws -> BrushImportResult {
        BrushImportResult(presets: try BrushPresetStore.decodeLibrary(data))
    }

    static func encode(_ presets: [BrushPreset]) throws -> Data {
        try BrushPresetStore.encodeLibrary(presets)
    }
}
