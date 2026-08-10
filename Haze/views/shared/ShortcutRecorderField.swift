//
//  ShortcutRecorderField.swift
//  Haze — views/shared
//

import SwiftUI
import AppKit

struct ShortcutRecorderField: NSViewRepresentable {
    var shortcut: ActionShortcut?
    var onCapture: (ActionShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let v = RecorderButton()
        v.onCapture = onCapture
        v.shortcut = shortcut
        v.refreshTitle()
        return v
    }

    func updateNSView(_ v: RecorderButton, context: Context) {
        v.onCapture = onCapture
        if !v.isRecording { v.shortcut = shortcut; v.refreshTitle() }
    }
}

final class RecorderButton: NSButton {
    var shortcut: ActionShortcut?
    var onCapture: ((ActionShortcut?) -> Void)?
    private(set) var isRecording = false { didSet { refreshTitle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        target = self
        action = #selector(arm)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    @objc private func arm() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { isRecording = false; return true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53:
            endRecording()
        case 51, 117:
            onCapture?(nil); endRecording()
        default:
            if let sc = ActionShortcut(event: event) { onCapture?(sc) }
            endRecording()
        }
    }

    private func endRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    func refreshTitle() {
        title = isRecording ? "Press keys…" : (shortcut?.display ?? "—")
    }
}
