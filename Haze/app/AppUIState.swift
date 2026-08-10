//
//  AppUIState.swift
//  Haze — app
//

import SwiftUI
import Combine
import AppKit

@MainActor
final class AppUIState: ObservableObject {
    @Published var showResizeCanvas = false
    @Published var showSettings = false
    @Published var showCommandPalette = false
    @Published var showNewCanvas = false
    @Published var showWelcome = true

    @Published var isEditingText = false
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?

    init() {
        let nc = NotificationCenter.default
        nc.publisher(for: NSText.didBeginEditingNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.isEditingText = true } }
            .store(in: &cancellables)
        nc.publisher(for: NSText.didEndEditingNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.isEditingText = false } }
            .store(in: &cancellables)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.syncEditingFromFirstResponder() }
            return event
        }
    }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    private func syncEditingFromFirstResponder() {
        let editing = (NSApp.keyWindow?.firstResponder as? NSTextView)?.isFieldEditor ?? false
        if editing != isEditingText { isEditingText = editing }
    }
}
