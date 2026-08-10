//
//  BrushIOCommand.swift
//  Haze — app
//

import AppKit
import UniformTypeIdentifiers
import OSLog

@MainActor
enum BrushIOCommand {

    private static func type(forExt ext: String) -> UTType {
        UTType(filenameExtension: ext) ?? .data
    }

    static func importBrushes(into presets: BrushPresetStore, store: Store) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = BrushPresetIO.readableExtensions.map(type(forExt:))
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var added = 0
        var skipped: [String] = []
        var failed: [String] = []
        for url in panel.urls {
            do {
                let result = try BrushPresetIO.importFile(at: url)
                added += presets.merge(result.presets)
                skipped += result.skipped
            } catch {
                failed.append(url.lastPathComponent)
                Log.app.error("Brush import failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error))")
            }
        }

        if added > 0 {
            var msg = "Imported \(added) preset\(added == 1 ? "" : "s")"
            if !skipped.isEmpty { msg += " · \(skipped.count) skipped" }
            store.notices.post(msg, .info)
        } else if !failed.isEmpty {
            store.notices.post("Import failed: \(failed.joined(separator: ", "))", .error)
        } else {
            store.notices.post("No presets found to import", .info)
        }
    }

    static func exportBrushes(_ presets: BrushPresetStore, store: Store) {
        guard !presets.presets.isEmpty else {
            store.notices.post("No presets to export", .info); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type(forExt: "hazebrush")]
        panel.nameFieldStringValue = "MyBrushes.hazebrush"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try BrushPresetIO.exportFile(presets.presets, to: url, using: HazeBrushCodec.self)
            store.notices.post("Exported \(presets.presets.count) presets", .info)
            Log.app.info("Exported brushes to \(url.path, privacy: .public)")
        } catch {
            store.notices.post("Export failed: \(error.localizedDescription)", .error)
            Log.app.error("Brush export failed: \(String(describing: error))")
        }
    }
}
