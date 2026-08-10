//
//  DiagnosticsReport.swift
//  Haze — diagnostics
//

import Foundation
import AppKit
import OSLog

enum DiagnosticsReport {

    static func directory() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true) else {
            Log.app.error("Could not resolve Application Support directory")
            return nil
        }
        let dir = base.appendingPathComponent("Haze/Diagnostics", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func write(_ name: String, _ text: String) -> URL? {
        guard let dir = directory() else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Log.app.error("Failed to write \(name, privacy: .public): \(String(describing: error))")
            return nil
        }
    }

    static func consumeSentinel(_ name: String) -> Bool {
        guard let dir = directory() else { return false }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }

    static func revealInFinder() {
        guard let dir = directory() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
