//
//  ResourceCache.swift
//  Haze — render
//

import Metal

@MainActor
final class ResourceCache {
    private let device: MTLDevice
    private var stores: [PixelTarget: LayerStore] = [:]
    private var selectionStores: [CanvasID: SelectionStore] = [:]

    var tilingEnabled = false
    var tileSize = 256

    init(device: MTLDevice) { self.device = device }

    func store(for target: PixelTarget, canvas: Canvas) -> LayerStore? {
        if let s = stores[target] { return s }
        let store: LayerStore? = tilingEnabled
            ? TiledLayerStore(device: device, width: canvas.width, height: canvas.height,
                              tileSize: tileSize, colorMode: canvas.colorMode)
            : SingleTextureLayerStore(device: device, width: canvas.width, height: canvas.height,
                                      colorMode: canvas.colorMode)
        if let store {
            stores[target] = store
            Invariants.require(store.width == canvas.width && store.height == canvas.height,
                               "layer store must match canvas size")
        }
        return store
    }

    func drop(_ target: PixelTarget) { stores[target] = nil }

    func dropAll() { stores.removeAll() }

    var layerStoreBytes: Int { stores.values.reduce(0) { $0 + $1.byteCount } }

    // MARK: - Selection mask (per canvas)

    func selection(for canvas: Canvas) -> SelectionStore? {
        if let s = selectionStores[canvas.id], s.width == canvas.width, s.height == canvas.height {
            return s
        }
        let s = SelectionStore(device: device, width: canvas.width, height: canvas.height)
        selectionStores[canvas.id] = s
        return s
    }

    func dropSelection(_ id: CanvasID) { selectionStores[id] = nil }

    // MARK: - Region read/write (pixel diffs, snapshots, import)

    func read(_ target: PixelTarget, rect: PixelRect, canvas: Canvas) -> [UInt8]? {
        store(for: target, canvas: canvas)?.read(rect)
    }

    func write(_ target: PixelTarget, rect: PixelRect, bytes: [UInt8], canvas: Canvas) {
        store(for: target, canvas: canvas)?.write(rect, bytes: bytes)
    }
}
