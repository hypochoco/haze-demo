//
//  InputView.swift
//  Haze — input
//

import AppKit
import Metal
import Combine
import simd

final class InputView: NSView {
    private let store: Store
    private let ui: AppUIState
    private var metalLayer: CAMetalLayer!
    private var cancellable: AnyCancellable?
    private var editorCancellable: AnyCancellable?
    private var uiCancellable: AnyCancellable?
    private var displayLink: CADisplayLink?
    private var pendingRender = false

    private var inputSuspended = false

    private var cursorContainer: CALayer?
    private let cursorBack = CAShapeLayer()
    private let cursorFront = CAShapeLayer()
    private let cursorDot = CAShapeLayer()
    private var pointerInside = false
    private var osCursorHidden = false
    private var lastMouseView: CGPoint?
    private var outlineCache: [UUID: [[CGPoint]]] = [:]

    private var camera = Camera()
    private var cameraReady = false
    private var fittedCanvasID: CanvasID?

    var selDraft: [SIMD2<Float>] = []
    var selRubber: SIMD2<Float>?
    var selDraftOp: SelectionOp = .replace
    let antsCommitted = CAShapeLayer()
    let antsCommittedBack = CAShapeLayer()
    let antsDraft = CAShapeLayer()
    let antsClip = CALayer()
    var antsClipOrigin: SIMD2<Float> = .zero
    var antsInstalled = false
    private var moveStart: SIMD2<Float> = .zero

    let txOverlay = CAShapeLayer()
    private var txInstalled = false
    private enum TxMode { case none, translate, rotate, scale }
    private var txMode: TxMode = .none
    private var txM0 = matrix_identity_float3x3
    private var txDownCanvas: SIMD2<Float> = .zero
    private var txCenterWorld: SIMD2<Float> = .zero
    private var txDownAngle: Float = 0
    private var txAnchorLocal: SIMD2<Float> = .zero
    private var txDraggedLocal: SIMD2<Float> = .zero
    private var txScaleX = false, txScaleY = false
    private var lastActiveTool: ToolKind = .brush

    init(store: Store, ui: AppUIState) {
        self.store = store
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        NSEvent.isMouseCoalescingEnabled = false
        cancellable = store.$document
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRender() }
        editorCancellable = store.$editor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.editorStateChanged() }
        uiCancellable = ui.$showCommandPalette
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in self?.setInputSuspended(open) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    deinit { displayLink?.invalidate(); if osCursorHidden { NSCursor.unhide() } }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { !inputSuspended }

    private func setInputSuspended(_ suspended: Bool) {
        guard suspended != inputSuspended else { return }
        inputSuspended = suspended
        if suspended, window?.firstResponder == self { window?.makeFirstResponder(nil) }
        updateCursorVisibility()
    }

    // MARK: - Frame-coalesced present (CADisplayLink)

    private func scheduleRender() {
        pendingRender = true
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(onFrame))
            link.add(to: .current, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    @objc private func onFrame() {
        if pendingRender {
            pendingRender = false
            render()
        } else {
            displayLink?.isPaused = true
        }
    }

    // MARK: - Pointer input → canvas-space → active tool (present is coalesced)

    override func mouseDown(with event: NSEvent) {
        positionCursor(event)
        let tool = store.editor.activeTool
        if isSampling(tool, event) { eyedropperSample(event) }
        else if tool.isSelection { selectionMouseDown(canvasPoint(event), event.modifierFlags) }
        else if tool == .move { moveMouseDown(canvasPoint(event)) }
        else if tool == .transform { transformMouseDown(event) }
        else { store.toolInput(canvasPoint(event), pressure: pressure(event), phase: .begin) }
        scheduleRender()
    }
    override func mouseDragged(with event: NSEvent) {
        positionCursor(event)
        let tool = store.editor.activeTool
        if isSampling(tool, event) { eyedropperSample(event) }
        else if tool.isSelection { selectionMouseDragged(canvasPoint(event)) }
        else if tool == .move { moveMouseDragged(canvasPoint(event)) }
        else if tool == .transform { transformMouseDragged(event) }
        else { store.toolInput(canvasPoint(event), pressure: pressure(event), phase: .moved) }
        scheduleRender()
    }
    override func mouseUp(with event: NSEvent) {
        positionCursor(event)
        let tool = store.editor.activeTool
        if isSampling(tool, event) {  }
        else if tool.isSelection { selectionMouseUp(canvasPoint(event)) }
        else if tool == .move { moveMouseUp(canvasPoint(event)) }
        else if tool == .transform { transformMouseUp(event) }
        else { store.toolInput(canvasPoint(event), pressure: pressure(event), phase: .ended) }
        scheduleRender()
    }

    // MARK: - Eyedropper

    private func isSampling(_ tool: ToolKind, _ event: NSEvent) -> Bool {
        tool == .eyedropper || (tool == .brush && event.modifierFlags.contains(.option))
    }

    private func eyedropperSample(_ event: NSEvent) {
        if let c = store.sampleColor(atCanvas: canvasPoint(event).simd) {
            store.foregroundColor = c
        }
    }

    // MARK: - Brush cursor (hover ring)

    override func mouseEntered(with event: NSEvent) {
        setupCursorLayerIfNeeded()
        updateCursorGeometry()
        positionCursor(event)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    override func mouseMoved(with event: NSEvent) {
        if store.editor.activeTool == .polygonLasso, !selDraft.isEmpty {
            selRubber = canvasPoint(event).simd
            scheduleRender()
        }
        positionCursor(event)
    }

    override func keyDown(with event: NSEvent) {
        if store.editor.activeTool == .polygonLasso, !selDraft.isEmpty {
            switch event.keyCode {
            case 36, 76: closePolygon(); scheduleRender(); return
            case 53:     cancelSelectionDraft(); scheduleRender(); return
            default:     break
            }
        }
        if store.editor.activeTool == .move, store.isFloating, event.keyCode == 53 {
            store.cancelFloatingMove(); scheduleRender(); return
        }
        if store.editor.activeTool == .transform, store.isTransforming {
            switch event.keyCode {
            case 36, 76: store.commitFloatingTransform(); scheduleRender(); return
            case 53:     store.cancelFloatingTransform(); scheduleRender(); return
            default:     break
            }
        }
        super.keyDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil))
    }

    // MARK: - Camera (pan / zoom)

    private var boundsPts: SIMD2<Float> { [Float(bounds.width), Float(bounds.height)] }

    private func fitCameraIfNeeded() {
        guard bounds.width > 0, bounds.height > 0, let canvas = store.activeCanvas else { return }
        let id = canvas.id
        if !cameraReady || fittedCanvasID != id {
            camera = .fitted(canvasWidth: canvas.width,
                             canvasHeight: canvas.height, viewPoints: boundsPts)
            cameraReady = true
            fittedCanvasID = id
        }
    }

    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let pv = SIMD2<Float>(Float(p.x), Float(p.y))
        let anchor = camera.canvasPoint(pv, viewPoints: boundsPts)
        camera.zoom = camera.clampedZoom(camera.zoom * Float(1 + event.magnification))
        camera.centerCanvas = anchor - (pv - boundsPts / 2) / camera.zoom
        afterCameraChange(at: p)
    }

    override func scrollWheel(with event: NSEvent) {
        let mult: Float = event.hasPreciseScrollingDeltas ? 1 : 10
        let dx = Float(event.scrollingDeltaX) * mult
        let dy = Float(event.scrollingDeltaY) * mult
        camera.centerCanvas.x -= dx / camera.zoom
        camera.centerCanvas.y -= dy / camera.zoom
        afterCameraChange(at: convert(event.locationInWindow, from: nil))
    }

    override func smartMagnify(with event: NSEvent) {
        guard let canvas = store.activeCanvas else { return }
        camera = .fitted(canvasWidth: canvas.width,
                         canvasHeight: canvas.height, viewPoints: boundsPts)
        afterCameraChange(at: convert(event.locationInWindow, from: nil))
    }

    private func afterCameraChange(at p: CGPoint) {
        if let canvas = store.activeCanvas {
            camera.clampCenter(canvasWidth: canvas.width, canvasHeight: canvas.height, viewPoints: boundsPts)
        }
        lastMouseView = p
        if shouldShowRing { updateCursorGeometry(); placeCursor(at: p) }
        scheduleRender()
    }

    private func setupCursorLayerIfNeeded() {
        guard cursorContainer == nil, let metalLayer else { return }
        let c = CALayer()
        c.isHidden = true
        c.zPosition = 1000
        cursorBack.fillColor = NSColor.clear.cgColor
        cursorBack.strokeColor = NSColor.black.withAlphaComponent(0.7).cgColor
        cursorBack.lineWidth = 2.5
        cursorFront.fillColor = NSColor.clear.cgColor
        cursorFront.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        cursorFront.lineWidth = 1
        cursorDot.fillColor = NSColor.white.cgColor
        cursorDot.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        cursorDot.lineWidth = 0.5
        let s = window?.backingScaleFactor ?? 2
        for l in [c, cursorBack, cursorFront, cursorDot] { l.contentsScale = s }
        c.addSublayer(cursorBack); c.addSublayer(cursorFront); c.addSublayer(cursorDot)
        metalLayer.addSublayer(c)
        cursorContainer = c
    }

    private func updateCursorGeometry() {
        guard let c = cursorContainer else { return }
        let radiusView = max(0.5, CGFloat(store.editor.brush.size) * CGFloat(camera.zoom) / 2)
        let b = store.editor.brush
        let angle = CGFloat(b.angleRadians)
        let roundness = CGFloat(b.roundness)
        let contours = b.tipID.map { cachedTipContours($0) } ?? BrushCursorOutline.roundContour()
        let placed = BrushCursorOutline.place(contours, radiusView: radiusView, angle: angle, roundness: roundness)

        var maxExtent = radiusView
        for loop in placed { for p in loop { maxExtent = max(maxExtent, max(abs(p.x), abs(p.y))) } }
        let pad: CGFloat = 4
        let side = 2 * maxExtent + pad
        let mid = side / 2

        let path = CGMutablePath()
        for loop in placed where loop.count >= 2 {
            path.move(to: CGPoint(x: mid + loop[0].x, y: mid + loop[0].y))
            for i in 1..<loop.count { path.addLine(to: CGPoint(x: mid + loop[i].x, y: mid + loop[i].y)) }
            path.closeSubpath()
        }

        CATransaction.begin(); CATransaction.setDisableActions(true)
        c.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        for l in [cursorBack, cursorFront, cursorDot] { l.frame = c.bounds }
        cursorBack.path = path; cursorFront.path = path
        cursorDot.path = CGPath(ellipseIn: CGRect(x: mid - 0.75, y: mid - 0.75, width: 1.5, height: 1.5), transform: nil)
        CATransaction.commit()
    }

    private func cachedTipContours(_ id: UUID) -> [[CGPoint]] {
        if let cached = outlineCache[id] { return cached }
        let contours: [[CGPoint]]
        if let (bytes, w) = store.render.tipCoverage(for: id) {
            let c = BrushCursorOutline.tipContours(coverage: bytes, width: w)
            contours = c.isEmpty ? BrushCursorOutline.roundContour() : c
        } else {
            contours = BrushCursorOutline.roundContour()
        }
        outlineCache[id] = contours
        return contours
    }

    private func placeCursor(at p: CGPoint) {
        guard let c = cursorContainer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        c.position = p
        CATransaction.commit()
    }

    private func positionCursor(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastMouseView = p
        setupCursorLayerIfNeeded()
        placeCursor(at: p)
        setPointerInside(bounds.contains(p))
    }

    // MARK: - Cursor visibility (single source of truth)

    private var shouldShowRing: Bool {
        !inputSuspended && store.editor.activeTool.isPaint && pointerInside
    }

    private func setPointerInside(_ inside: Bool) {
        pointerInside = inside
        updateCursorVisibility()
    }

    private func updateCursorVisibility() {
        let show = shouldShowRing
        if show { setupCursorLayerIfNeeded() }
        cursorContainer?.isHidden = !show
        setOSCursorHidden(show)
    }

    private func setOSCursorHidden(_ hidden: Bool) {
        guard hidden != osCursorHidden else { return }
        osCursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
    }

    private func refreshCursorForBrushChange() {
        guard shouldShowRing else { return }
        updateCursorGeometry()
        if let p = lastMouseView { placeCursor(at: p) }
    }

    private func editorStateChanged() {
        let tool = store.editor.activeTool
        if tool != lastActiveTool {
            if lastActiveTool == .transform, store.isTransforming { store.commitFloatingTransform() }
            if tool == .transform, !store.isTransforming,
               store.activeCanvas?.pixelSelection.isActive == true {
                store.beginFloatingTransform()
                window?.makeFirstResponder(self)
            }
            lastActiveTool = tool
        }
        refreshCursorForBrushChange()
        updateCursorVisibility()
        scheduleRender()
    }

    private func pressure(_ event: NSEvent) -> Float {
        let p = event.pressure
        return p > 0 ? p : 1
    }

    private func canvasPoint(_ event: NSEvent) -> CanvasPoint {
        let pt = convert(event.locationInWindow, from: nil)
        let c = camera.canvasPoint([Float(pt.x), Float(pt.y)], viewPoints: boundsPts)
        return CanvasPoint(c.x, c.y)
    }

    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = store.render.device
        l.pixelFormat = RenderContext.pixelFormat
        l.framebufferOnly = true
        l.isOpaque = true
        l.masksToBounds = true
        metalLayer = l
        return l
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setOSCursorHidden(false); pointerInside = false; return }
        setupCursorLayerIfNeeded()
        updateScaleAndSize()
        scheduleRender()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScaleAndSize()
        scheduleRender()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateScaleAndSize()
        scheduleRender()
    }

    private func updateScaleAndSize() {
        guard let metalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        for l in [cursorContainer, cursorBack, cursorFront, cursorDot] { l?.contentsScale = scale }
        fitCameraIfNeeded()
        if shouldShowRing {
            updateCursorGeometry()
            if let p = lastMouseView { placeCursor(at: p) }
        }
    }

    private func render() {
        guard let metalLayer,
              metalLayer.drawableSize.width > 0, metalLayer.drawableSize.height > 0 else { return }
        guard let canvas = store.activeCanvas else { presentEmpty(metalLayer); return }
        let space = canvas.colorMode.space.cgColorSpace
        if metalLayer.colorspace?.name != space.name { metalLayer.colorspace = space }
        guard let composite = store.render.compositeTexture(width: canvas.width, height: canvas.height,
                                                            format: canvas.colorMode.mtlPixelFormat) else { return }
        if !store.renderStrokeFrame(into: composite) {
            store.renderFallbackComposite(into: composite)
        }
        if let fp = store.floatingPreview() {
            store.render.drawOver(fp.tex, into: composite, canvasRect: fp.rect,
                                  canvasW: canvas.width, canvasH: canvas.height, wait: false)
        }
        if let tp = store.floatingTransformPreview() {
            store.render.drawOverQuad(tp.tex, into: composite,
                                      topLeft: tp.tl, topRight: tp.tr, bottomLeft: tp.bl, bottomRight: tp.br,
                                      canvasW: canvas.width, canvasH: canvas.height, wait: false)
        }

        guard let drawable = metalLayer.nextDrawable() else { return }
        fitCameraIfNeeded()
        let viewport = SIMD2<Float>(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height))
        var mvp = camera.matrix(canvasWidth: canvas.width, canvasHeight: canvas.height,
                                viewport: viewport, backingScale: Float(metalLayer.contentsScale))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.12, 0.12, 0.12, 1)
        pass.colorAttachments[0].storeAction = .store

        guard let cb = store.render.queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(store.render.presentPipeline)
        enc.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 0)
        enc.setFragmentTexture(composite, index: 0)
        enc.setFragmentSamplerState(store.render.sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
        updateSelectionOverlay()
    }

    private func presentEmpty(_ metalLayer: CAMetalLayer) {
        updateSelectionOverlay()
        guard let drawable = metalLayer.nextDrawable(),
              let cb = store.render.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.12, 0.12, 0.12, 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    // MARK: - Selection tools (lasso / polygon lasso)

    private func selectionMouseDown(_ p: CanvasPoint, _ mods: NSEvent.ModifierFlags) {
        window?.makeFirstResponder(self)
        let pt = p.simd
        switch store.editor.activeTool {
        case .lasso:
            selDraft = [pt]; selRubber = nil
            selDraftOp = SelectionOp(mods)
        case .polygonLasso:
            if selDraft.isEmpty { selDraftOp = SelectionOp(mods) }
            selDraft.append(pt); selRubber = pt
        default: break
        }
    }

    private func selectionMouseDragged(_ p: CanvasPoint) {
        guard store.editor.activeTool == .lasso else { return }
        selDraft.append(p.simd)
    }

    private func selectionMouseUp(_ p: CanvasPoint) {
        guard store.editor.activeTool == .lasso else { return }
        selDraft.append(p.simd)
        commitDraft()
    }

    private func closePolygon() { commitDraft() }

    private func commitDraft() {
        let pts = selDraft
        let op = selDraftOp
        selDraft = []; selRubber = nil; selDraftOp = .replace
        if pts.count >= 3 { store.setSelection(subpaths: [pts], op: op) }
        scheduleRender()
    }

    func cancelSelectionDraft() { selDraft = []; selRubber = nil; selDraftOp = .replace; scheduleRender() }

    // MARK: - Move tool (floating selection)

    private func moveMouseDown(_ p: CanvasPoint) {
        window?.makeFirstResponder(self)
        moveStart = p.simd
        store.beginFloatingMove()
    }
    private func moveMouseDragged(_ p: CanvasPoint) {
        guard store.isFloating else { return }
        store.setFloatingOffset(p.simd - moveStart)
    }
    private func moveMouseUp(_ p: CanvasPoint) {
        guard store.isFloating else { return }
        store.setFloatingOffset(p.simd - moveStart)
        store.commitFloatingMove()
    }

    // MARK: - Free transform (gizmo)

    private struct TxHandle { let u: Float; let v: Float; let sx: Bool; let sy: Bool }
    private static let txHandles: [TxHandle] = [
        .init(u: 0, v: 0, sx: true, sy: true), .init(u: 1, v: 0, sx: true, sy: true),
        .init(u: 1, v: 1, sx: true, sy: true), .init(u: 0, v: 1, sx: true, sy: true),
        .init(u: 0.5, v: 0, sx: false, sy: true), .init(u: 1, v: 0.5, sx: true, sy: false),
        .init(u: 0.5, v: 1, sx: false, sy: true), .init(u: 0, v: 0.5, sx: true, sy: false),
    ]

    private func txLocal(_ u: Float, _ v: Float, _ s: PixelRect) -> SIMD2<Float> {
        [Float(s.x) + u * Float(s.width), Float(s.y) + v * Float(s.height)]
    }

    private func transformMouseDown(_ event: NSEvent) {
        guard store.isTransforming, let M = store.transformMatrix, let s = store.transformSourceBounds else {
            store.beginFloatingTransform()
            window?.makeFirstResponder(self)
            return
        }
        if event.clickCount >= 2 { store.commitFloatingTransform(); return }

        let p = canvasPoint(event).simd
        let opt = event.modifierFlags.contains(.option)
        txM0 = M
        txDownCanvas = p
        let centerLocal = txLocal(0.5, 0.5, s)
        txCenterWorld = Affine.apply(M, centerLocal)

        let hitR = Float(9) / max(camera.zoom, 0.0001)
        var best: (TxHandle, Float)? = nil
        for h in Self.txHandles {
            let d = simd_distance(p, Affine.apply(M, txLocal(h.u, h.v, s)))
            if d < hitR, best == nil || d < best!.1 { best = (h, d) }
        }
        if let (h, _) = best {
            txMode = .scale
            txScaleX = h.sx; txScaleY = h.sy
            txDraggedLocal = txLocal(h.u, h.v, s)
            txAnchorLocal = opt ? centerLocal : txLocal(1 - h.u, 1 - h.v, s)
            return
        }
        if txPointInBox(p, M, s) {
            txMode = .translate
        } else {
            txMode = .rotate
            txDownAngle = atan2(p.y - txCenterWorld.y, p.x - txCenterWorld.x)
        }
    }

    private func transformMouseDragged(_ event: NSEvent) {
        guard store.isTransforming, txMode != .none else { return }
        let p = canvasPoint(event).simd
        let shift = event.modifierFlags.contains(.shift)
        switch txMode {
        case .translate:
            store.setTransformMatrix(Affine.translate(p - txDownCanvas) * txM0)
        case .rotate:
            var a = atan2(p.y - txCenterWorld.y, p.x - txCenterWorld.x) - txDownAngle
            if shift { let step = Float.pi / 12; a = (a / step).rounded() * step }
            store.setTransformMatrix(Affine.rotate(a, about: txCenterWorld) * txM0)
        case .scale:
            let ml = Affine.apply(txM0.inverse, p)
            var sx: Float = 1, sy: Float = 1
            if txScaleX, txDraggedLocal.x != txAnchorLocal.x {
                sx = (ml.x - txAnchorLocal.x) / (txDraggedLocal.x - txAnchorLocal.x)
            }
            if txScaleY, txDraggedLocal.y != txAnchorLocal.y {
                sy = (ml.y - txAnchorLocal.y) / (txDraggedLocal.y - txAnchorLocal.y)
            }
            if shift, txScaleX, txScaleY {
                let m = max(abs(sx), abs(sy))
                sx = Float(sx < 0 ? -m : m); sy = Float(sy < 0 ? -m : m)
            }
            store.setTransformMatrix(txM0 * Affine.scale([sx, sy], about: txAnchorLocal))
        case .none:
            break
        }
    }

    private func transformMouseUp(_ event: NSEvent) { txMode = .none }

    private func txPointInBox(_ p: SIMD2<Float>, _ M: simd_float3x3, _ s: PixelRect) -> Bool {
        let c = [txLocal(0, 0, s), txLocal(1, 0, s), txLocal(1, 1, s), txLocal(0, 1, s)].map { Affine.apply(M, $0) }
        var sign: Float = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(cross) < 1e-4 { continue }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        return true
    }

    // MARK: - Marching-ants overlay

    func updateSelectionOverlay() {
        guard let metalLayer else { return }
        installAntsIfNeeded(on: metalLayer)
        installTxIfNeeded(on: metalLayer)
        CATransaction.begin(); CATransaction.setDisableActions(true)

        if let canvas = store.activeCanvas {
            let origin = camera.viewPoint([0, 0], viewPoints: boundsPts)
            let z = CGFloat(camera.zoom)
            antsClip.frame = CGRect(x: CGFloat(origin.x), y: CGFloat(origin.y),
                                    width: CGFloat(canvas.width) * z, height: CGFloat(canvas.height) * z)
            for l in [antsCommittedBack, antsCommitted, antsDraft] { l.frame = antsClip.bounds }
            antsClipOrigin = origin
            let transforming = store.isTransforming

            if canvas.pixelSelection.isActive && !transforming {
                let drag = store.floatingOffset.map {
                    SIMD2<Float>(Float(Int($0.x.rounded())), Float(Int($0.y.rounded())))
                } ?? .zero
                let path = antsPath(for: canvas.pixelSelection, offset: drag)
                antsCommitted.path = path; antsCommittedBack.path = path
                antsCommitted.isHidden = false; antsCommittedBack.isHidden = false
            } else {
                antsCommitted.isHidden = true; antsCommittedBack.isHidden = true
            }
            if !selDraft.isEmpty {
                antsDraft.path = draftPath(); antsDraft.isHidden = false
            } else {
                antsDraft.isHidden = true
            }
            if transforming, let M = store.transformMatrix, let s = store.transformSourceBounds {
                txOverlay.frame = bounds
                txOverlay.path = txGizmoPath(M, s)
                txOverlay.isHidden = false
            } else {
                txOverlay.isHidden = true
            }
        } else {
            antsCommitted.isHidden = true; antsCommittedBack.isHidden = true; antsDraft.isHidden = true
            txOverlay.isHidden = true
        }
        CATransaction.commit()
    }

    private func txGizmoPath(_ M: simd_float3x3, _ s: PixelRect) -> CGPath {
        func vp(_ u: Float, _ v: Float) -> CGPoint {
            let q = camera.viewPoint(Affine.apply(M, txLocal(u, v, s)), viewPoints: boundsPts)
            return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
        }
        let path = CGMutablePath()
        let corners = [vp(0, 0), vp(1, 0), vp(1, 1), vp(0, 1)]
        path.move(to: corners[0]); for c in corners.dropFirst() { path.addLine(to: c) }; path.closeSubpath()
        let r: CGFloat = 4
        for h in Self.txHandles {
            let c = vp(h.u, h.v)
            path.addRect(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return path
    }

    private func installTxIfNeeded(on layer: CALayer) {
        guard !txInstalled else { return }
        txOverlay.zPosition = 950
        txOverlay.fillColor = NSColor.clear.cgColor
        txOverlay.strokeColor = NSColor.systemBlue.cgColor
        txOverlay.lineWidth = 1
        txOverlay.contentsScale = window?.backingScaleFactor ?? 2
        layer.addSublayer(txOverlay)
        txInstalled = true
    }

    private func installAntsIfNeeded(on layer: CALayer) {
        guard !antsInstalled else { return }
        let scale = window?.backingScaleFactor ?? 2
        antsClip.masksToBounds = true
        antsClip.zPosition = 900
        layer.addSublayer(antsClip)
        for l in [antsCommittedBack, antsCommitted, antsDraft] {
            l.fillColor = NSColor.clear.cgColor
            l.contentsScale = scale
            antsClip.addSublayer(l)
        }
        antsCommittedBack.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        antsCommittedBack.lineWidth = 1.5
        antsCommitted.strokeColor = NSColor.white.cgColor
        antsCommitted.lineWidth = 1
        antsCommitted.lineDashPattern = [4, 4]
        let anim = CABasicAnimation(keyPath: "lineDashPhase")
        anim.fromValue = 0; anim.toValue = 8
        anim.duration = 0.5; anim.repeatCount = .infinity
        antsCommitted.add(anim, forKey: "ants")
        antsDraft.strokeColor = NSColor.systemBlue.cgColor
        antsDraft.lineWidth = 1
        antsDraft.lineDashPattern = [3, 3]
        antsInstalled = true
    }

    private func antsPath(for sel: SelectionState, offset: SIMD2<Float> = .zero) -> CGPath {
        let path = CGMutablePath()
        if sel.path.isEmpty {
            let b = sel.bounds
            addLoop([[Float(b.x), Float(b.y)], [Float(b.x + b.width), Float(b.y)],
                     [Float(b.x + b.width), Float(b.y + b.height)], [Float(b.x), Float(b.y + b.height)]],
                    closed: true, offset: offset, to: path)
        } else {
            for sub in sel.path { addLoop(sub, closed: true, offset: offset, to: path) }
        }
        return path
    }

    private func draftPath() -> CGPath {
        let path = CGMutablePath()
        var pts = selDraft
        if store.editor.activeTool == .polygonLasso, let r = selRubber { pts.append(r) }
        addLoop(pts, closed: false, offset: .zero, to: path)
        return path
    }

    private func addLoop(_ canvasPts: [SIMD2<Float>], closed: Bool, offset: SIMD2<Float>, to path: CGMutablePath) {
        guard canvasPts.count >= 2 else { return }
        let o = antsClipOrigin
        func v(_ p: SIMD2<Float>) -> CGPoint {
            let q = camera.viewPoint(p + offset, viewPoints: boundsPts)
            return CGPoint(x: CGFloat(q.x - o.x), y: CGFloat(q.y - o.y))
        }
        path.move(to: v(canvasPts[0]))
        for p in canvasPts.dropFirst() { path.addLine(to: v(p)) }
        if closed { path.closeSubpath() }
    }
}
