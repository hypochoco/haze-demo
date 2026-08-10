//
//  SelectionStore.swift
//  Haze — render
//

import Metal

@MainActor
final class SelectionStore {
    private let device: MTLDevice
    private(set) var width: Int
    private(set) var height: Int
    private(set) var texture: MTLTexture

    init?(device: MTLDevice, width: Int, height: Int) {
        guard let tex = Self.makeMask(device, width, height) else { return nil }
        self.device = device
        self.width = width
        self.height = height
        self.texture = tex
    }

    func readAll() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: width,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return bytes
    }

    func write(_ rect: PixelRect, bytes: [UInt8]) {
        guard !rect.isEmpty, bytes.count == rect.width * rect.height else { return }
        bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: rect.width)
        }
    }

    func read(_ rect: PixelRect) -> [UInt8]? {
        guard !rect.isEmpty else { return nil }
        var bytes = [UInt8](repeating: 0, count: rect.width * rect.height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: rect.width,
                             from: MTLRegionMake2D(rect.x, rect.y, rect.width, rect.height), mipmapLevel: 0)
        }
        return bytes
    }

    func clear() {
        let zero = [UInt8](repeating: 0, count: width * height)
        write(PixelRect(x: 0, y: 0, width: width, height: height), bytes: zero)
    }

    static func makeMask(_ device: MTLDevice, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: max(1, w), height: max(1, h), mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        let zero = [UInt8](repeating: 0, count: max(1, w) * max(1, h))
        zero.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, max(1, w), max(1, h)),
                        mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: max(1, w))
        }
        return tex
    }
}
