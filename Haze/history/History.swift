//
//  History.swift
//  Haze — history
//

@MainActor
final class History {
    private(set) var undoStack: [Command] = []
    private(set) var redoStack: [Command] = []

    var byteBudget: Int = .max
    private(set) var byteCount = 0

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func record(_ command: Command) {
        for c in redoStack { byteCount -= c.byteCost }
        redoStack.removeAll()

        undoStack.append(command)
        byteCount += command.byteCost
        evictIfNeeded()
    }

    @discardableResult
    func undo(_ ctx: CommandContext) -> Command? {
        guard let command = undoStack.popLast() else { return nil }
        command.revert(ctx)
        redoStack.append(command)
        return command
    }

    @discardableResult
    func redo(_ ctx: CommandContext) -> Command? {
        guard let command = redoStack.popLast() else { return nil }
        command.apply(ctx)
        undoStack.append(command)
        return command
    }

    private func evictIfNeeded() {
        while byteCount > byteBudget, undoStack.count > 1 {
            let removed = undoStack.removeFirst()
            byteCount -= removed.byteCost
        }
    }
}
