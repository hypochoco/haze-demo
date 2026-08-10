//
//  BrushTool.swift
//  Haze — tools
//

import Metal
import simd

@MainActor
final class BrushTool: Tool {
    private var gen: DabGenerator?
    private var scratch: MTLTexture?
    private var opacity: Float = 1
    private var tipTex: MTLTexture?
    private var roundness: Float = 1
    private var ceiling: MTLTexture?
    private var resolved: MTLTexture?
    private var useCeiling = false
    private(set) var erasing = false
    private var bounds: (minX: Float, minY: Float, maxX: Float, maxY: Float)?
    private var frameDirty: (minX: Float, minY: Float, maxX: Float, maxY: Float)?
    private(set) var isStroking = false

    func takeFrameDirty(canvasWidth: Int, canvasHeight: Int) -> PixelRect? {
        defer { frameDirty = nil }
        guard let b = frameDirty else { return nil }
        return PixelRect.fromBounds(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY,
                                    canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    }

    var preview: (texture: MTLTexture, opacity: Float)? {
        guard isStroking else { return nil }
        if useCeiling, let resolved { return (resolved, opacity) }
        guard let scratch else { return nil }
        return (scratch, opacity)
    }

    func resolvePreview(dirty: PixelRect?, ctx: RenderContext) {
        guard useCeiling, let scratch, let ceiling, let resolved else { return }
        ctx.resolveScratch(scratch, ceiling: ceiling, into: resolved, dirty: dirty)
    }

    func handle(_ input: ToolInput, _ ctx: ToolContext) {
        switch input.phase {
        case .begin:
            guard let scratch = ctx.render.scratchTexture(width: ctx.canvas.width,
                                                          height: ctx.canvas.height,
                                                          format: ctx.canvas.colorMode.mtlPixelFormat) else { return }
            ctx.render.fill(scratch, premul: [0, 0, 0, 0])
            self.scratch = scratch
            self.opacity = ctx.brush.opacity
            self.erasing = ctx.erase
            self.tipTex = ctx.brush.tipID.flatMap { ctx.render.tipTexture(for: $0) }
            self.roundness = ctx.brush.roundness
            self.useCeiling = ctx.brush.pressureOpacity > 0
            if useCeiling {
                let fmt = ctx.canvas.colorMode.mtlPixelFormat
                self.ceiling = ctx.render.ceilingTexture(width: ctx.canvas.width, height: ctx.canvas.height)
                self.resolved = ctx.render.resolvedScratchTexture(width: ctx.canvas.width, height: ctx.canvas.height, format: fmt)
                if let ceiling { ctx.render.fill(ceiling, premul: [0, 0, 0, 0]) }
                if let resolved { ctx.render.fill(resolved, premul: [0, 0, 0, 0]) }
            } else {
                self.ceiling = nil; self.resolved = nil
            }
            self.bounds = nil
            self.frameDirty = nil
            self.isStroking = true
            var g = DabGenerator(radius: ctx.brush.radius, spacing: ctx.brush.spacingPx,
                                 flow: ctx.brush.flow,
                                 pressureSize: ctx.brush.pressureSize, pressureFlow: ctx.brush.pressureFlow,
                                 pressureOpacity: ctx.brush.pressureOpacity,
                                 angle: ctx.brush.angleRadians, angleJitter: ctx.brush.angleJitter,
                                 sizeJitter: ctx.brush.sizeJitter, scatter: ctx.brush.scatter,
                                 angleFollowsDirection: ctx.brush.angleFollowsDirection)
            let dabs = g.begin(input.point.simd, pressure: input.pressure)
            gen = g
            accumulate(dabs, ctx)

        case .moved:
            guard var g = gen else { return }
            let dabs = g.extend(to: input.point.simd, pressure: input.pressure)
            gen = g
            accumulate(dabs, ctx)

        case .ended:
            if var g = gen {
                let dabs = g.extend(to: input.point.simd, pressure: input.pressure)
                gen = g
                accumulate(dabs, ctx)
            }
            commit(ctx)
            gen = nil
            scratch = nil
            tipTex = nil
            ceiling = nil
            resolved = nil
            useCeiling = false
            bounds = nil
            isStroking = false
        }
    }

    private func accumulate(_ dabs: [Dab], _ ctx: ToolContext) {
        guard !dabs.isEmpty, let scratch else { return }
        let boundScale = tipTex != nil ? BrushStamper.footprintScale : 1
        for d in dabs { expandBounds(center: d.center, radius: d.radius * boundScale) }
        BrushStamper.stamp(dabs, color: ctx.brush.color, hardness: ctx.brush.hardness,
                           tip: tipTex, roundness: roundness,
                           into: scratch, ceiling: useCeiling ? ceiling : nil, ctx: ctx.render)
    }

    private func expandBounds(center: SIMD2<Float>, radius: Float) {
        let r = max(0.5, radius)
        let nx0 = center.x - r, ny0 = center.y - r, nx1 = center.x + r, ny1 = center.y + r
        if var b = bounds {
            b.minX = min(b.minX, nx0); b.minY = min(b.minY, ny0)
            b.maxX = max(b.maxX, nx1); b.maxY = max(b.maxY, ny1)
            bounds = b
        } else {
            bounds = (nx0, ny0, nx1, ny1)
        }
        if var f = frameDirty {
            f.minX = min(f.minX, nx0); f.minY = min(f.minY, ny0)
            f.maxX = max(f.maxX, nx1); f.maxY = max(f.maxY, ny1)
            frameDirty = f
        } else {
            frameDirty = (nx0, ny0, nx1, ny1)
        }
    }

    private func commit(_ ctx: ToolContext) {
        guard let scratch,
              let b = bounds,
              let rect = PixelRect.fromBounds(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY,
                                              canvasWidth: ctx.canvas.width, canvasHeight: ctx.canvas.height) else { return }
        let source: MTLTexture
        if useCeiling, let ceiling, let resolved {
            ctx.render.resolveScratch(scratch, ceiling: ceiling, into: resolved, dirty: rect)
            source = resolved
        } else {
            source = scratch
        }
        let command = PixelEditRecorder.capture(target: ctx.target, rect: rect, canvas: ctx.canvas,
                                                render: ctx.render, tileSize: ctx.tileSize, title: erasing ? "Erase" : "Brush") {
            if let store = ctx.render.resources.store(for: ctx.target, canvas: ctx.canvas) {
                store.blendScratch(source, dirty: rect, opacity: opacity, mask: ctx.selectionMask, erase: erasing, ctx: ctx.render)
            }
        }
        if let command { ctx.record(command) }
    }
}
