//
//  PSDExport.swift
//  Haze — io
//

import Metal

@MainActor
enum PSDExport {

    static func canvasImage(from canvas: Canvas, render: RenderContext, fileName: String) -> CanvasImage {
        let w = canvas.width, h = canvas.height

        var layers: [LayerImage] = []
        appendNodes(canvas.nodes, into: &layers, canvas: canvas, render: render)

        var image = CanvasImage(fileName: fileName, width: w, height: h, layers: layers,
                                depth: canvas.colorMode.depth, space: canvas.colorMode.space,
                                dpi: canvas.dpi)

        if let target = render.compositeTexture(width: w, height: h, format: canvas.colorMode.mtlPixelFormat) {
            Compositor.composite(canvas, into: target, ctx: render)
            render.flush()
            let raw = RenderContext.readBytes(from: target)
            image.flattenedOverride = PixelConversion.premultipliedBGRAToStraightRGBA(raw)
        }

        return image
    }

    private static func appendNodes(_ nodes: [LayerNode], into layers: inout [LayerImage],
                                    canvas: Canvas, render: RenderContext) {
        let w = canvas.width, h = canvas.height
        let rect = PixelRect(x: 0, y: 0, width: w, height: h)
        let empty = [UInt8](repeating: 0, count: w * h * 4)
        for node in nodes {
            switch node {
            case .layer(let l):
                let straight: [UInt8]
                if let raw = render.resources.read(.layer(l.id), rect: rect, canvas: canvas) {
                    straight = PixelConversion.premultipliedBGRAToStraightRGBA(raw)
                } else {
                    straight = empty
                }
                layers.append(LayerImage(name: l.name, isVisible: l.isVisible, opacity: l.opacity,
                                         blendMode: l.blend, pixels: straight, divider: .none))
            case .group(let g):
                layers.append(LayerImage(name: "</Layer group>", isVisible: true, opacity: 1,
                                         blendMode: .normal,
                                         pixels: empty, divider: .bounding))
                appendNodes(g.children, into: &layers, canvas: canvas, render: render)
                layers.append(LayerImage(name: g.name, isVisible: g.isVisible, opacity: g.opacity,
                                         blendMode: g.blend,
                                         pixels: empty, divider: g.isExpanded ? .open : .closed))
            }
        }
    }

    private static func grayscalePlane(fromStraightRGBA straight: [UInt8], count: Int, sixteen: Bool) -> [UInt8] {
        if sixteen {
            var out = [UInt8](repeating: 0, count: count * 2)
            for i in 0..<count {
                let s = i * 8
                if s + 1 < straight.count { out[i * 2] = straight[s]; out[i * 2 + 1] = straight[s + 1] }
            }
            return out
        } else {
            var out = [UInt8](repeating: 0, count: count)
            for i in 0..<count { let s = i * 4; if s < straight.count { out[i] = straight[s] } }
            return out
        }
    }

    static func encode(_ canvas: Canvas, render: RenderContext, fileName: String) throws -> Data {
        try PSDCodec().encode(canvasImage(from: canvas, render: render, fileName: fileName))
    }
}
