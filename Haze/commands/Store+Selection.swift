//
//  Store+Selection.swift
//  Haze — commands
//

import simd

extension Store {

    func setSelection(subpaths: [[SIMD2<Float>]], op: SelectionOp = .replace, title: String? = nil) {
        guard let canvas = requireCanvas("Selection") else { return }
        let w = canvas.width, h = canvas.height
        let raster = SelectionMaskRasterizer.rasterize(subpaths, width: w, height: h)

        if op == .replace {
            guard let (bounds, coverage) = raster else { deselect(); return }
            applyMaskChange(title: title ?? op.title, mutate: { store in
                store.clear()
                store.write(bounds, bytes: coverage)
            }, newState: { version in
                SelectionState(isActive: true, bounds: bounds, version: version, path: subpaths)
            })
            return
        }

        guard let store = render.resources.selection(for: canvas) else { return }
        guard let (b, cov) = raster else { return }
        let hadSelection = canvas.pixelSelection.isActive

        var newCov = [UInt8](repeating: 0, count: w * h)
        for row in 0..<b.height {
            let src = row * b.width, dst = (b.y + row) * w + b.x
            for col in 0..<b.width { newCov[dst + col] = cov[src + col] }
        }

        let old = store.readAll()
        var combined = old
        switch op {
        case .add:       for i in 0..<combined.count { combined[i] = max(old[i], newCov[i]) }
        case .subtract:  for i in 0..<combined.count { combined[i] = UInt8(Int(old[i]) * (255 - Int(newCov[i])) / 255) }
        case .intersect: for i in 0..<combined.count { combined[i] = UInt8(Int(old[i]) * Int(newCov[i]) / 255) }
        case .replace:   break
        }

        if combined == old { return }
        let (bounds, active) = Self.boundsOfNonZero(combined, width: w, height: h)
        if !active && !hadSelection { return }

        let path = active ? SelectionContourTracer.trace(mask: combined, width: w, height: h) : []
        applyMaskChange(title: title ?? op.title, mutate: { s in
            s.clear()
            s.write(PixelRect(x: 0, y: 0, width: w, height: h), bytes: combined)
        }, newState: { version in
            active ? SelectionState(isActive: true, bounds: bounds, version: version, path: path) : .none
        })
    }

    func selectAll(title: String = "Select All") {
        guard let canvas = requireCanvas("Select All") else { return }
        let full = PixelRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        applyMaskChange(title: title, mutate: { store in
            store.clear()
            store.write(full, bytes: [UInt8](repeating: 255, count: full.width * full.height))
        }, newState: { version in
            SelectionState(isActive: true, bounds: full, version: version, path: [])
        })
    }

    func deselect(title: String = "Deselect") {
        guard let canvas = requireCanvas("Deselect") else { return }
        guard canvas.pixelSelection.isActive else { return }
        applyMaskChange(title: title, mutate: { $0.clear() }, newState: { _ in .none })
    }

    func invertSelection(title: String = "Invert Selection") {
        guard let canvas = requireCanvas("Invert Selection"),
              let store = render.resources.selection(for: canvas) else { return }
        let full = PixelRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let current = store.read(full) ?? [UInt8](repeating: 0, count: full.width * full.height)
        var inverted = current
        for i in 0..<inverted.count { inverted[i] = 255 - inverted[i] }
        let (b, active) = Self.boundsOfNonZero(inverted, width: full.width, height: full.height)
        applyMaskChange(title: title, mutate: { s in
            s.clear(); s.write(full, bytes: inverted)
        }, newState: { version in
            active ? SelectionState(isActive: true, bounds: b, version: version, path: []) : .none
        })
    }

    // MARK: - Core

    private func applyMaskChange(title: String, mutate: (SelectionStore) -> Void,
                                 newState: (Int) -> SelectionState) {
        guard let canvas = activeCanvas, let store = render.resources.selection(for: canvas) else { return }
        let oldBounds = canvas.pixelSelection.isActive ? canvas.pixelSelection.bounds : nil
        let before = oldBounds.map { MaskSnapshot.capture(canvas, render: render, tileSize: config.tileSize, within: $0) }
            ?? MaskSnapshot(state: canvas.pixelSelection, tiles: [])

        mutate(store)
        let state = newState(canvas.pixelSelection.version + 1)
        updateActiveSelectionState(state)

        let afterTiles = state.isActive
            ? MaskSnapshot.nonEmptyTiles(store, tileSize: config.tileSize, within: state.bounds)
            : []
        let after = MaskSnapshot(state: state, tiles: afterTiles)
        record(SetSelectionCommand(title: title, before: before, after: after))
    }

    static func boundsOfNonZero(_ bytes: [UInt8], width: Int, height: Int) -> (PixelRect, Bool) {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let base = y * width
            for x in 0..<width where bytes[base + x] != 0 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return (PixelRect(x: 0, y: 0, width: 0, height: 0), false) }
        return (PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), true)
    }
}
