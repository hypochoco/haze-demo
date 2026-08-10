//
//  CanvasCloseCommand.swift
//  Haze — app
//

import AppKit

@MainActor
enum CanvasCloseCommand {

    @discardableResult
    static func close(_ id: CanvasID, store: Store) -> Bool {
        guard store.document.canvas(id) != nil else { return true }
        guard store.isDirty(id) else { store.closeCanvas(id); return true }

        let name = store.document.canvas(id)?.name ?? "this canvas"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes you made to “\(name)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.selectCanvas(id)
            PSDSaveCommand.save(store: store)
            if store.isDirty(id) { return false }
            store.closeCanvas(id)
            return true
        case .alertThirdButtonReturn:
            store.closeCanvas(id)
            return true
        default:
            return false
        }
    }

    static func makeRoomForNewCanvas(store: Store) -> Bool {
        guard let current = store.activeCanvas else { return true }
        return close(current.id, store: store)
    }
}
