//
//  Store.swift
//  Haze — store
//

import Combine
import Foundation
import OSLog
import Metal

@MainActor
final class Store: ObservableObject {
    @Published private(set) var document: Document
    @Published var editor = EditorState()
    let render: RenderContext
    let config: Config
    let notices = NoticeCenter()
    @Published var selection: Set<LayerID> = []

    @Published var selectionAnchor: LayerID?

    private var histories: [CanvasID: History] = [:]
    private var canvasFiles: [CanvasID: URL] = [:]
    @Published private(set) var dirtyCanvasIDs: Set<CanvasID> = []

    @MainActor static weak var current: Store?

    private let brushTool = BrushTool()

    var floating: FloatingSelection?
    let canvasNeedsDisplay = PassthroughSubject<Void, Never>()

    var floatingTransform: FloatingTransform?

    let contentVersions = ContentVersions()
    let thumbnailCache = LayerThumbnailCache()

    func layerContentVersion(_ id: LayerID) -> Int { contentVersions.version(id) }

    func bumpContent(_ ids: [LayerID]) {
        contentVersions.bump(ids)
    }

    init(document: Document, render: RenderContext, config: Config) {
        self.document = document
        self.render = render
        self.config = config
        render.resources.tilingEnabled = config.tilingEnabled
        render.resources.tileSize = config.tileSize
    }

    convenience init(canvas: Canvas, render: RenderContext, config: Config) {
        self.init(document: Document(single: canvas), render: render, config: config)
    }

    func configDidChange() {
        let bytes = config.historyByteBudgetMB * 1_048_576
        for h in histories.values { h.byteBudget = bytes }
    }

    static func makeDefault() -> Store {
        guard let render = RenderContext() else {
            fatalError("Haze requires a Metal-capable GPU.")
        }
        let store = Store(document: Document(canvases: [], activeCanvasID: nil), render: render, config: Config())
        Store.current = store
        return store
    }

    func fillWhiteBase(in canvas: Canvas) {
        guard let id = canvas.nodes.leaves.first?.id else { return }
        let rect = PixelRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let white = [UInt8](repeating: 255, count: canvas.width * canvas.height * canvas.colorMode.bytesPerPixel)
        render.resources.write(.layer(id), rect: rect, bytes: white, canvas: canvas)
    }

    // MARK: - Active canvas

    var hasCanvas: Bool { !document.canvases.isEmpty }

    var activeCanvas: Canvas? { document.activeCanvas }

    @discardableResult
    func requireCanvas(_ what: String = "That action") -> Canvas? {
        guard let canvas = document.activeCanvas else {
            notices.post("\(what) needs an open canvas", .warning)
            return nil
        }
        return canvas
    }

    private var activeHistory: History? { document.activeCanvas.map { history(for: $0.id) } }

    private func history(for id: CanvasID) -> History {
        if let h = histories[id] { return h }
        let h = History()
        h.byteBudget = config.historyByteBudgetMB * 1_048_576
        histories[id] = h
        return h
    }

    var historyDebugInfo: HistoryDebugInfo {
        let budget = config.historyByteBudgetMB * 1_048_576
        guard let canvas = document.activeCanvas else {
            return HistoryDebugInfo(canvasName: "—", undo: [], redo: [], byteCount: 0, byteBudget: budget)
        }
        guard let h = histories[canvas.id] else {
            return HistoryDebugInfo(canvasName: canvas.name, undo: [], redo: [],
                                    byteCount: 0, byteBudget: budget)
        }
        func entries(_ stack: [Command]) -> [HistoryDebugInfo.Entry] {
            stack.enumerated().map { .init(index: $0.offset, title: $0.element.title, byteCost: $0.element.byteCost) }
        }
        return HistoryDebugInfo(canvasName: canvas.name,
                                undo: entries(h.undoStack), redo: entries(h.redoStack),
                                byteCount: h.byteCount, byteBudget: h.byteBudget)
    }

    private func setActiveCanvas(_ canvas: Canvas) {
        Invariants.checkTree(canvas)
        if let i = document.activeIndex { document.canvases[i] = canvas }
    }

    func updateActiveSelectionState(_ state: SelectionState) {
        if let i = document.activeIndex { document.canvases[i].pixelSelection = state }
    }

    // MARK: - Document ops (not undoable)

    func newCanvas(width: Int = 1024, height: Int = 1024,
                   name: String? = nil,
                   background: CanvasBackground = .white,
                   dpi: Double? = nil) {
        var canvas = Canvas.makeDefault(width: width, height: height)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        canvas.name = (trimmed?.isEmpty == false ? trimmed! : "Canvas \(document.canvases.count + 1)")
        canvas.colorMode = .default
        canvas.dpi = dpi ?? Double(config.newCanvasDPI)
        if background == .transparent, let baseID = canvas.nodes.leaves.first?.id {
            canvas.updateLayer(baseID) { $0.name = "Layer 1" }
        }
        document.canvases.append(canvas)
        document.activeCanvasID = canvas.id
        selection = []
        if background == .white { fillWhiteBase(in: canvas) }
    }

    func selectCanvas(_ id: CanvasID) {
        if document.canvas(id) != nil { document.activeCanvasID = id; selection = [] }
    }

    var canvasCount: Int { document.canvases.count }

    func cycleCanvas(by delta: Int) {
        let cs = document.canvases
        guard cs.count > 1, let i = cs.firstIndex(where: { $0.id == document.activeCanvasID }) else { return }
        let n = cs.count
        selectCanvas(cs[((i + delta) % n + n) % n].id)
    }

    func openCanvas(_ image: CanvasImage, fileURL: URL? = nil) {
        let w = image.width, h = image.height
        let (nodes, leafPixels) = Store.reconstructNodes(image.layers)
        let usedFallback = nodes.isEmpty
        let finalNodes: [LayerNode] = usedFallback ? [.layer(Layer(name: "Background"))] : nodes
        let canvas = Canvas(name: image.fileName, width: w, height: h,
                            nodes: finalNodes, selectedLayerID: finalNodes.leaves.last?.id,
                            colorMode: ColorMode(depth: image.depth, space: image.space),
                            dpi: image.dpi)

        let rect = PixelRect(x: 0, y: 0, width: w, height: h)
        let expectedBytes = w * h * canvas.colorMode.bytesPerPixel
        for (id, pixels) in leafPixels {
            let target = PixelTarget.layer(id)
            _ = render.resources.store(for: target, canvas: canvas)
            guard pixels.count == expectedBytes else { continue }
            let premul = PixelConversion.straightRGBAToPremultipliedBGRA(pixels)
            render.resources.write(target, rect: rect, bytes: premul, canvas: canvas)
        }
        if usedFallback { fillWhiteBase(in: canvas) }

        document.canvases.append(canvas)
        document.activeCanvasID = canvas.id
        if let fileURL { canvasFiles[canvas.id] = fileURL }
    }

    static func reconstructNodes(_ images: [LayerImage]) -> (nodes: [LayerNode], leafPixels: [(LayerID, [UInt8])]) {
        var frames: [[LayerNode]] = [[]]
        var leaves: [(LayerID, [UInt8])] = []
        for li in images {
            switch li.divider {
            case .bounding:
                frames.append([])
            case .none:
                let layer = Layer(name: li.name, isVisible: li.isVisible, opacity: li.opacity,
                                  blend: li.blendMode)
                frames[frames.count - 1].append(.layer(layer))
                leaves.append((layer.id, li.pixels))
            case .open, .closed:
                guard frames.count >= 2 else { continue }
                let children = frames.removeLast()
                let group = LayerGroup(name: li.name, isVisible: li.isVisible, opacity: li.opacity,
                                       blend: li.blendMode, isExpanded: li.divider == .open, children: children)
                frames[frames.count - 1].append(.group(group))
            }
        }
        if frames.count != 1 {
            return (frames.flatMap { $0 }, leaves)
        }
        return (frames[0], leaves)
    }

    func fileURL(forCanvas id: CanvasID) -> URL? { canvasFiles[id] }
    func setFileURL(_ url: URL, forCanvas id: CanvasID) { canvasFiles[id] = url }

    func resizeCanvas(width newW: Int, height newH: Int,
                      anchor: ResizeAnchor = .topLeft, method: ResizeMethod = .cropExtend) {
        guard let canvas = requireCanvas("Resize Canvas") else { return }
        guard newW > 0, newH > 0, newW != canvas.width || newH != canvas.height else { return }
        let offset = anchor.offset(oldW: canvas.width, oldH: canvas.height, newW: newW, newH: newH)
        let snaps: [ResizeCanvasCommand.LayerSnap] = canvas.layers.map { layer in
            .init(id: layer.id,
                  snapshot: LayerSnapshot.capture(.layer(layer.id), canvas: canvas,
                                                  render: render, tileSize: config.tileSize))
        }
        perform(ResizeCanvasCommand(oldSize: (canvas.width, canvas.height),
                                    newSize: (newW, newH), offset: offset, method: method,
                                    layers: snaps))
    }

    func selectLayer(_ id: LayerID) {
        guard let i = document.activeIndex, document.canvases[i].nodes.contains(nodeID: id) else { return }
        document.canvases[i].selectedLayerID = id
        selection = [id]
        selectionAnchor = id
    }

    func extendSelection(to id: LayerID) {
        guard let i = document.activeIndex else { return }
        let canvas = document.canvases[i]
        guard canvas.nodes.contains(nodeID: id) else { return }
        let anchor = selectionAnchor ?? canvas.selectedLayerID
        let order = canvas.nodes.visibleOrderIDs()
        guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) else {
            selectLayer(id); return
        }
        selection = Set(order[(Swift.min(a, b))...(Swift.max(a, b))])
        document.canvases[i].selectedLayerID = id
    }

    func reconcileSelection() {
        guard let canvas = activeCanvas else { selection = []; return }
        var next = selection.filter { canvas.nodes.contains(nodeID: $0) }
        if let primary = canvas.selectedLayerID { next.insert(primary) }
        if next != selection { selection = next }
    }

    func toggleSelection(_ id: LayerID) {
        guard let i = document.activeIndex, document.canvases[i].nodes.contains(nodeID: id) else { return }
        if selection.contains(id) {
            selection.remove(id)
            if document.canvases[i].selectedLayerID == id { document.canvases[i].selectedLayerID = selection.first }
        } else {
            selection.insert(id)
            document.canvases[i].selectedLayerID = id
        }
        selectionAnchor = id
    }

    func setGroupExpanded(_ id: LayerID, _ expanded: Bool) {
        guard let i = document.activeIndex else { return }
        document.canvases[i].updateGroup(id) { $0.isExpanded = expanded }
    }

    func previewLayerOpacity(_ id: LayerID, _ value: Float) {
        guard let i = document.activeIndex else { return }
        document.canvases[i].updateLayer(id) { $0.opacity = value }
    }

    func previewGroupOpacity(_ id: LayerID, _ value: Float) {
        guard let i = document.activeIndex else { return }
        document.canvases[i].updateGroup(id) { $0.opacity = value }
    }

    func commitLayerOpacity(_ id: LayerID, from old: Float) {
        guard let current = activeCanvas?.layer(id)?.opacity, current != old else { return }
        perform(MutateCommand(
            title: "Layer Opacity",
            doApply: { ctx in ctx.canvas.updateLayer(id) { $0.opacity = current } },
            doRevert: { ctx in ctx.canvas.updateLayer(id) { $0.opacity = old } }))
    }

    func closeCanvas(_ id: CanvasID) {
        guard document.canvas(id) != nil else { return }
        if let c = document.canvas(id) {
            for layer in c.layers {
                render.resources.drop(.layer(layer.id))
            }
        }
        histories[id] = nil
        canvasFiles[id] = nil
        dirtyCanvasIDs.remove(id)
        render.resources.dropSelection(id)
        document.canvases.removeAll { $0.id == id }
        if document.activeCanvasID == id { document.activeCanvasID = document.canvases.last?.id }
        selection = []
    }

    // MARK: - Commands / history (active canvas)

    func perform(_ command: Command) {
        guard let canvas = requireCanvas(command.title) else { return }
        let ctx = CommandContext(canvas: canvas, render: render, config: config)
        command.apply(ctx)
        setActiveCanvas(ctx.canvas)
        history(for: canvas.id).record(command)
        bumpContent(command.affectedLayers)
        markDirty(canvas.id)
        Log.history.debug("performed \(command.title, privacy: .public)")
    }

    func record(_ command: Command) {
        guard let h = activeHistory else { return }
        h.record(command)
        bumpContent(command.affectedLayers)
        markDirty(document.activeCanvasID)
        objectWillChange.send()
        Log.history.debug("recorded \(command.title, privacy: .public)")
    }

    var canUndo: Bool { activeHistory?.canUndo ?? false }
    var canRedo: Bool { activeHistory?.canRedo ?? false }
    var historyByteCount: Int { activeHistory?.byteCount ?? 0 }

    // MARK: - Unsaved-changes tracking (quit save-prompt)

    var hasUnsavedChanges: Bool { !dirtyCanvasIDs.isEmpty }
    func isDirty(_ id: CanvasID) -> Bool { dirtyCanvasIDs.contains(id) }
    func markDirty(_ id: CanvasID?) { if let id { dirtyCanvasIDs.insert(id) } }
    func markSaved(_ id: CanvasID) { dirtyCanvasIDs.remove(id) }

    func undo() {
        guard let canvas = activeCanvas, let h = activeHistory, h.canUndo else { return }
        let ctx = CommandContext(canvas: canvas, render: render, config: config)
        let command = h.undo(ctx)
        setActiveCanvas(ctx.canvas)
        bumpContent(command?.affectedLayers ?? [])
        markDirty(canvas.id)
        reconcileSelection()
    }

    func redo() {
        guard let canvas = activeCanvas, let h = activeHistory, h.canRedo else { return }
        let ctx = CommandContext(canvas: canvas, render: render, config: config)
        let command = h.redo(ctx)
        setActiveCanvas(ctx.canvas)
        bumpContent(command?.affectedLayers ?? [])
        markDirty(canvas.id)
        reconcileSelection()
    }

    // MARK: - Painting (transient GPU side-effect; commits to a recorded command)

    func toolInput(_ p: CanvasPoint, pressure: Float = 1, phase: ToolInput.Phase) {
        switch editor.activeTool {
        case .brush, .eraser:
            switch phase {
            case .begin: strokeBegin(p, pressure: pressure)
            case .moved: strokeMoved(p, pressure: pressure)
            case .ended: strokeEnded(p, pressure: pressure)
            }
        case .lasso, .polygonLasso, .move, .transform, .eyedropper:
            break
        }
    }

    func strokeBegin(_ p: CanvasPoint, pressure: Float = 1) {
        drive(p, .begin, pressure)
        if brushTool.isStroking, let canvas = activeCanvas, let a = canvas.selectedLayerID {
            strokeFast = strokeCompositor.begin(canvas: canvas, activeID: a,
                                                maskTex: nil, paintingMask: false)
            strokeFirstFrame = strokeFast
        } else {
            strokeFast = false
        }
    }
    func strokeMoved(_ p: CanvasPoint, pressure: Float = 1) { drive(p, .moved, pressure) }
    func strokeEnded(_ p: CanvasPoint, pressure: Float = 1) {
        drive(p, .ended, pressure)
        strokeCompositor.end()
        strokeFast = false
    }

    func renderFallbackComposite(into composite: MTLTexture) {
        guard let canvas = activeCanvas else { return }
        Compositor.composite(canvas, into: composite, ctx: render, wait: false)
        guard let preview = strokePreview() else { return }
        let erasing = isErasingStroke
        let clip = overlayClipMask(for: canvas)
        switch (erasing, clip) {
        case (false, let m?): render.blendMasked(preview.texture, mask: m, into: composite, opacity: preview.opacity)
        case (false, nil):    render.blend(preview.texture, into: composite, opacity: preview.opacity)
        case (true,  let m?): render.eraseMasked(preview.texture, mask: m, into: composite, opacity: preview.opacity)
        case (true,  nil):    render.erase(preview.texture, into: composite, opacity: preview.opacity)
        }
    }

    private func overlayClipMask(for canvas: Canvas) -> MTLTexture? {
        if let sel = activeSelectionMask(for: canvas) { return sel }
        return nil
    }

    private lazy var strokeCompositor = StrokeCompositor(ctx: render)
    private var strokeFast = false
    private var strokeFirstFrame = false

    func renderStrokeFrame(into composite: MTLTexture) -> Bool {
        guard strokeFast, let canvas = activeCanvas, let a = canvas.selectedLayerID,
              let activeTex = render.resources.store(for: .layer(a), canvas: canvas)?.materialize(ctx: render)
        else { return false }
        let preview = brushTool.preview
        let mask = activeSelectionMask(for: canvas)
        if strokeFirstFrame {
            strokeFirstFrame = false
            brushTool.resolvePreview(dirty: nil, ctx: render)
            strokeCompositor.frame(into: composite, activeTex: activeTex, scratch: preview?.texture,
                                   previewOpacity: preview?.opacity ?? 0, dirty: nil, selectionMask: mask, erase: brushTool.erasing)
            return true
        }
        guard let dirty = brushTool.takeFrameDirty(canvasWidth: canvas.width,
                                                   canvasHeight: canvas.height) else { return true }
        brushTool.resolvePreview(dirty: dirty, ctx: render)
        strokeCompositor.frame(into: composite, activeTex: activeTex, scratch: preview?.texture,
                               previewOpacity: preview?.opacity ?? 0, dirty: dirty, selectionMask: mask, erase: brushTool.erasing)
        return true
    }

    private func drive(_ p: CanvasPoint, _ phase: ToolInput.Phase, _ pressure: Float) {
        guard let canvas = activeCanvas else {
            if phase == .begin { notices.post("Open a canvas to paint", .warning) }
            return
        }
        guard selection.count <= 1 else {
            if phase == .begin { notices.post("Select a single layer to paint on", .error) }
            return
        }
        guard let layer = canvas.selectedLayer else {
            if phase == .begin {
                notices.post(canvas.layers.isEmpty ? "Add a layer to paint on" : "Select a layer to paint on", .warning)
            }
            return
        }
        guard layer.isVisible else {
            if phase == .begin { notices.post("Can’t paint on a hidden layer", .error) }
            return
        }
        let target: PixelTarget = .layer(layer.id)
        let brush = editor.brush
        let ctx = ToolContext(render: render, canvas: canvas,
                              target: target, brush: brush,
                              tileSize: config.tileSize,
                              record: { [weak self] command in self?.record(command) },
                              selectionMask: activeSelectionMask(for: canvas),
                              erase: editor.activeTool == .eraser)
        brushTool.handle(ToolInput(point: p, pressure: pressure, phase: phase), ctx)
    }

    func activeSelectionMask(for canvas: Canvas) -> MTLTexture? {
        guard canvas.pixelSelection.isActive else { return nil }
        return render.resources.selection(for: canvas)?.texture
    }

    func strokePreview() -> (texture: MTLTexture, opacity: Float)? {
        brushTool.resolvePreview(dirty: nil, ctx: render)
        return brushTool.preview
    }

    var isErasingStroke: Bool { brushTool.isStroking && brushTool.erasing }
}
