//
//  ResizeCanvasCommand.swift
//  Haze — commands
//

enum ResizeAnchor: Hashable {
    case topLeft, center

    func offset(oldW: Int, oldH: Int, newW: Int, newH: Int) -> (dx: Int, dy: Int) {
        switch self {
        case .topLeft: return (0, 0)
        case .center:  return ((newW - oldW) / 2, (newH - oldH) / 2)
        }
    }
}

enum ResizeMethod {
    case cropExtend
    case resample
}

struct ResizeCanvasCommand: Command {
    struct LayerSnap {
        let id: LayerID
        let snapshot: LayerSnapshot
    }

    let oldSize: (w: Int, h: Int)
    let newSize: (w: Int, h: Int)
    let offset: (dx: Int, dy: Int)
    let method: ResizeMethod
    let layers: [LayerSnap]

    var title: String { "Resize Canvas" }
    var byteCost: Int { layers.reduce(0) { $0 + $1.snapshot.byteCount } }
    var affectedLayers: [LayerID] { layers.map(\.id) }

    func apply(_ ctx: CommandContext) {
        for l in layers {
            guard let store = ctx.render.resources.store(for: .layer(l.id), canvas: ctx.canvas) else { continue }
            switch method {
            case .cropExtend:
                store.cropExtend(toWidth: newSize.w, toHeight: newSize.h, offset: offset)
            case .resample:
                store.resample(toWidth: newSize.w, toHeight: newSize.h, ctx: ctx.render)
            }
        }
        ctx.canvas.width = newSize.w
        ctx.canvas.height = newSize.h
    }

    func revert(_ ctx: CommandContext) {
        ctx.canvas.width = oldSize.w
        ctx.canvas.height = oldSize.h
        for l in layers {
            ctx.render.resources.store(for: .layer(l.id), canvas: ctx.canvas)?
                .reallocateBlank(toWidth: oldSize.w, toHeight: oldSize.h)
            l.snapshot.restore(.layer(l.id), render: ctx.render, canvas: ctx.canvas)
        }
    }
}
