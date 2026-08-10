//
//  PSDSaveCommand.swift
//  Haze — app
//

import AppKit
import UniformTypeIdentifiers
import OSLog

@MainActor
enum PSDSaveCommand {

    static func save(store: Store) {
        guard let canvas = store.activeCanvas else {
            store.notices.post("Open a canvas to save", .warning); return
        }
        if let url = store.fileURL(forCanvas: canvas.id) {
            write(store: store, canvasID: canvas.id, to: url)
        } else {
            saveAs(store: store)
        }
    }

    static func saveAs(store: Store) {
        guard let canvas = store.activeCanvas else {
            store.notices.post("Open a canvas to save", .warning); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "psd") ?? .data]
        panel.nameFieldStringValue = canvas.name.lowercased().hasSuffix(".psd")
            ? canvas.name : "\(canvas.name).psd"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(store: store, canvasID: canvas.id, to: url)
    }

    private static func write(store: Store, canvasID: CanvasID, to url: URL) {
        guard let canvas = store.activeCanvas else { return }
        let data: Data
        do {
            data = try PSDExport.encode(canvas, render: store.render,
                                        fileName: url.deletingPathExtension().lastPathComponent)
        } catch {
            Log.app.error("PSD encode failed: \(String(describing: error))")
            store.notices.post("Couldn’t prepare PSD: \(error)", .error)
            return
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: url)
            store.setFileURL(url, forCanvas: canvasID)
            store.markSaved(canvasID)
            Log.app.info("Saved PSD to \(url.path, privacy: .public)")
            store.notices.post("Saved \(url.lastPathComponent)", .info)
        } catch {
            Log.app.error("PSD write failed: \(String(describing: error))")
            store.notices.post("Save failed: \(error.localizedDescription)", .error)
        }
    }
}
