//
//  Document.swift
//  Haze — model
//

struct Document: Equatable {
    var canvases: [Canvas]
    var activeCanvasID: CanvasID?

    init(canvases: [Canvas], activeCanvasID: CanvasID?) {
        self.canvases = canvases
        self.activeCanvasID = activeCanvasID
    }

    init(single canvas: Canvas) {
        self.canvases = [canvas]
        self.activeCanvasID = canvas.id
    }

    var activeIndex: Int? {
        guard let id = activeCanvasID else { return nil }
        return canvases.firstIndex { $0.id == id }
    }

    var activeCanvas: Canvas? {
        guard let i = activeIndex else { return nil }
        return canvases[i]
    }

    func canvas(_ id: CanvasID) -> Canvas? { canvases.first { $0.id == id } }
}
