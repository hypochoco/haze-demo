//
//  DocumentIOCommand.swift
//  Haze — app
//

import AppKit
import UniformTypeIdentifiers
import OSLog

@MainActor
enum DocumentIOCommand {

    // MARK: Open / Import

    static func open(store: Store) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentFormatRegistry.readableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let format = DocumentFormatRegistry.format(forExt: url.pathExtension) else {
            store.notices.post("Can’t open .\(url.pathExtension) files", .error); return
        }
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.deletingPathExtension().lastPathComponent
            let (unmasked, skippedMasks) = try format.decode(data, fileName: fileName).strippingMasks()
            let (image, depthConverted, spaceConverted) = unmasked.convertedToDemoFormat()
            guard CanvasCloseCommand.makeRoomForNewCanvas(store: store) else { return }
            store.openCanvas(image, fileURL: format.supportsLayers ? url : nil)
            Log.app.info("Opened \(url.path, privacy: .public)")
            store.notices.post("Opened \(url.lastPathComponent)", .info)
            if skippedMasks > 0 {
                store.notices.post(
                    "Skipped \(skippedMasks) layer mask\(skippedMasks == 1 ? "" : "s") — masks aren’t supported in this build",
                    .warning)
            }
            if depthConverted || spaceConverted {
                var parts: [String] = []
                if depthConverted { parts.append("16-bit → 8-bit") }
                if spaceConverted { parts.append("Display P3 → sRGB") }
                store.notices.post("Converted on open: \(parts.joined(separator: ", "))", .info)
            }
        } catch {
            Log.app.error("Open failed: \(String(describing: error))")
            store.notices.post("Open failed: \(error)", .error)
        }
    }

    // MARK: Export As…

    static func exportAs(store: Store) {
        guard let canvas = store.activeCanvas else {
            store.notices.post("Open a canvas to export", .warning); return
        }
        let formats = DocumentFormatRegistry.writable
        guard !formats.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = Self.baseName(canvas.name)

        let initial = formats.firstIndex { !$0.supportsLayers } ?? 0
        let accessory = ExportFormatAccessory(panel: panel, formats: formats, initialIndex: initial)
        panel.accessoryView = accessory.container
        accessory.syncPanelType()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let format = accessory.selectedFormat

        let data: Data
        do {
            let options = ImageExportOptions(jpegQuality: store.config.jpegQuality)
            data = try format.encode(canvas, render: store.render,
                                     fileName: url.deletingPathExtension().lastPathComponent, options: options)
        } catch {
            Log.app.error("Export encode failed: \(String(describing: error))")
            store.notices.post("Couldn’t prepare \(format.displayName): \(error)", .error)
            return
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: url)
            Log.app.info("Exported \(url.path, privacy: .public)")
            store.notices.post("Exported \(url.lastPathComponent)", .info)
        } catch {
            Log.app.error("Export write failed: \(String(describing: error))")
            store.notices.post("Export failed: \(error.localizedDescription)", .error)
        }
    }

    private static func baseName(_ name: String) -> String {
        let exts = Set(DocumentFormatRegistry.formats.flatMap { $0.fileExtensions })
        let url = URL(fileURLWithPath: name)
        return exts.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : name
    }
}

@MainActor
final class ExportFormatAccessory: NSObject {
    let container = NSView()
    private let popup = NSPopUpButton()
    private let formats: [ImageFormat.Type]
    private weak var panel: NSSavePanel?

    init(panel: NSSavePanel, formats: [ImageFormat.Type], initialIndex: Int) {
        self.formats = formats
        self.panel = panel
        super.init()

        let label = NSTextField(labelWithString: "Format:")
        popup.addItems(withTitles: formats.map { "\($0.displayName) (.\($0.fileExtensions[0]))" })
        popup.selectItem(at: max(0, min(initialIndex, formats.count - 1)))
        popup.target = self
        popup.action = #selector(formatChanged)

        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .firstBaseline
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.frame = NSRect(x: 0, y: 0, width: 340, height: 48)
    }

    var selectedFormat: ImageFormat.Type { formats[max(0, min(popup.indexOfSelectedItem, formats.count - 1))] }

    func syncPanelType() { panel?.allowedContentTypes = [selectedFormat.utType] }

    @objc private func formatChanged() { syncPanelType() }
}
