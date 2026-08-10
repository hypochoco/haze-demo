//
//  PSDCodec.swift
//  Haze — io
//

import Foundation
import CoreGraphics

struct PSDCodec: ImageDocumentCodec {

    static var fileExtensions: [String] { ["psd"] }

    static let maxDimension = 30_000

    private static let idRed: Int16 = 0
    private static let idGreen: Int16 = 1
    private static let idBlue: Int16 = 2
    private static let idAlpha: Int16 = -1
    private static let idMask: Int16 = -2

    // MARK: - Encode

    func encode(_ image: CanvasImage) throws -> Data {
        guard image.width > 0, image.height > 0 else {
            throw CodecError.malformed("zero-sized canvas")
        }
        guard image.width <= Self.maxDimension, image.height <= Self.maxDimension else {
            throw CodecError.unsupported("canvas exceeds PSD 30,000px limit (needs PSB)")
        }

        let w = image.width, h = image.height
        let bps = image.bytesPerSample
        var out = BinaryWriter()

        out.ascii("8BPS")
        out.u16(1)
        out.zeros(6)
        out.u16(4)
        out.u32(UInt32(h))
        out.u32(UInt32(w))
        out.u16(UInt16(bps * 8))
        out.u16(3)

        out.u32(0)
        out.raw(encodeImageResources(image))

        out.raw(encodeLayerAndMaskSection(image))

        let composite = image.mergedForEncoding()
        out.raw(encodeCompositeBlock(composite, width: w, height: h, bps: bps))

        return out.data
    }

    private func encodeLayerAndMaskSection(_ image: CanvasImage) -> Data {
        var layerInfo = BinaryWriter()
        layerInfo.i16(Int16(image.layers.count))

        let w = image.width, h = image.height
        let bps = image.bytesPerSample

        var encodedChannels: [[Data]] = []
        encodedChannels.reserveCapacity(image.layers.count)
        for layer in image.layers {
            var blocks: [Data] = []
            for ch in 0..<4 {
                blocks.append(encodeChannelBlock(layer.pixels, channel: ch, width: w, height: h, bps: bps))
            }
            if let mask = layer.maskPixels {
                blocks.append(encodeMaskChannelBlock(mask, width: w, height: h, bps: bps))
            }
            encodedChannels.append(blocks)
        }

        for (idx, layer) in image.layers.enumerated() {
            layerInfo.i32(0)
            layerInfo.i32(0)
            layerInfo.i32(Int32(h))
            layerInfo.i32(Int32(w))

            let chCount = encodedChannels[idx].count
            layerInfo.u16(UInt16(chCount))
            let ids: [Int16] = [Self.idRed, Self.idGreen, Self.idBlue, Self.idAlpha, Self.idMask]
            for ci in 0..<chCount {
                layerInfo.i16(ids[ci])
                layerInfo.u32(UInt32(encodedChannels[idx][ci].count))
            }

            layerInfo.ascii("8BIM")
            layerInfo.ascii(Self.psdBlendKey(layer.blendMode))
            layerInfo.u8(UInt8(max(0, min(255, (layer.opacity * 255).rounded()))))
            layerInfo.u8(0)
            layerInfo.u8(layer.isVisible ? 0x00 : 0x02)
            layerInfo.u8(0)

            let nameBlock = Self.pascalName(layer.name)
            let lsct = Self.lsctBlock(layer.divider)
            let maskData = layer.maskPixels != nil
                ? Self.layerMaskData(width: w, height: h, disabled: !layer.maskEnabled) : Data()
            let extraLen = 4 + maskData.count + 4 + nameBlock.count + lsct.count
            layerInfo.u32(UInt32(extraLen))
            layerInfo.u32(UInt32(maskData.count))
            if !maskData.isEmpty { layerInfo.raw(maskData) }
            layerInfo.u32(0)
            layerInfo.bytes(nameBlock)
            if !lsct.isEmpty { layerInfo.raw(lsct) }
        }

        for blocks in encodedChannels {
            for block in blocks { layerInfo.raw(block) }
        }

        var layerInfoData = layerInfo.data
        if layerInfoData.count % 2 != 0 { layerInfoData.append(0) }

        var body = BinaryWriter()
        body.u32(UInt32(layerInfoData.count))
        body.raw(layerInfoData)
        body.u32(0)

        var section = BinaryWriter()
        section.u32(UInt32(body.data.count))
        section.raw(body.data)
        return section.data
    }

    private func channelRow(_ pixels: [UInt8], channel: Int, row: Int, width: Int, bps: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * bps)
        let base = row * width
        if bps == 1 {
            for x in 0..<width { out[x] = pixels[(base + x) * 4 + channel] }
        } else {
            for x in 0..<width {
                let s = ((base + x) * 4 + channel) * 2
                let v = UInt16(pixels[s]) | (UInt16(pixels[s + 1]) << 8)
                out[x * 2] = UInt8(v >> 8); out[x * 2 + 1] = UInt8(v & 0xff)
            }
        }
        return out
    }

    private func encodeChannelBlock(_ pixels: [UInt8], channel: Int, width: Int, height: Int, bps: Int) -> Data {
        var counts: [UInt16] = []; counts.reserveCapacity(height)
        var packed = Data()
        for r in 0..<height {
            let enc = Self.packBits(channelRow(pixels, channel: channel, row: r, width: width, bps: bps))
            counts.append(UInt16(truncatingIfNeeded: enc.count))
            packed.append(contentsOf: enc)
        }
        var w = BinaryWriter()
        w.u16(1)
        for c in counts { w.u16(c) }
        w.raw(packed)
        return w.data
    }

    private func encodeMaskChannelBlock(_ plane: [UInt8], width: Int, height: Int, bps: Int) -> Data {
        var counts: [UInt16] = []; counts.reserveCapacity(height)
        var packed = Data()
        for r in 0..<height {
            let enc = Self.packBits(maskChannelRow(plane, row: r, width: width, bps: bps))
            counts.append(UInt16(truncatingIfNeeded: enc.count))
            packed.append(contentsOf: enc)
        }
        var w = BinaryWriter()
        w.u16(1)
        for c in counts { w.u16(c) }
        w.raw(packed)
        return w.data
    }

    private func maskChannelRow(_ plane: [UInt8], row: Int, width: Int, bps: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * bps)
        let base = row * width
        if bps == 1 {
            for x in 0..<width { out[x] = base + x < plane.count ? plane[base + x] : 0 }
        } else {
            for x in 0..<width {
                let s = (base + x) * 2
                let v = s + 1 < plane.count ? (UInt16(plane[s]) | (UInt16(plane[s + 1]) << 8)) : 0
                out[x * 2] = UInt8(v >> 8); out[x * 2 + 1] = UInt8(v & 0xff)
            }
        }
        return out
    }

    private static func layerMaskData(width: Int, height: Int, disabled: Bool) -> Data {
        var w = BinaryWriter()
        w.i32(0); w.i32(0); w.i32(Int32(height)); w.i32(Int32(width))
        w.u8(0)
        w.u8(disabled ? 0x02 : 0x00)
        w.u16(0)
        return w.data
    }

    private func encodeCompositeBlock(_ rgba: [UInt8], width: Int, height: Int, bps: Int) -> Data {
        var counts: [UInt16] = []
        var packed = Data()
        for channel in 0..<4 {
            for r in 0..<height {
                let enc = Self.packBits(channelRow(rgba, channel: channel, row: r, width: width, bps: bps))
                counts.append(UInt16(truncatingIfNeeded: enc.count))
                packed.append(contentsOf: enc)
            }
        }
        var w = BinaryWriter()
        w.u16(1)
        for c in counts { w.u16(c) }
        w.raw(packed)
        return w.data
    }

    static func packBits(_ src: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        let n = src.count
        var i = 0
        while i < n {
            var runEnd = i + 1
            while runEnd < n && src[runEnd] == src[i] && (runEnd - i) < 128 { runEnd += 1 }
            let runLen = runEnd - i
            if runLen >= 2 {
                out.append(UInt8(bitPattern: Int8(1 - runLen)))
                out.append(src[i])
                i = runEnd
            } else {
                var litEnd = i
                while litEnd < n && (litEnd - i) < 128 {
                    if litEnd + 1 < n && src[litEnd] == src[litEnd + 1] { break }
                    litEnd += 1
                }
                let litLen = litEnd - i
                out.append(UInt8(litLen - 1))
                out.append(contentsOf: src[i..<litEnd])
                i = litEnd
            }
        }
        return out
    }

    private static func psdBlendKey(_ mode: BlendMode) -> String {
        switch mode {
        case .normal:   return "norm"
        case .multiply: return "mul "
        case .screen:   return "scrn"
        }
    }

    static func blendMode(fromPSDKey key: String) -> BlendMode {
        switch key {
        case "mul ": return .multiply
        case "scrn": return .screen
        default:     return .normal
        }
    }

    // MARK: - Image resources (ICC colour profile)

    private static let iccResourceID: UInt16 = 0x040F
    private static let resolutionResourceID: UInt16 = 0x03ED

    private func encodeImageResources(_ image: CanvasImage) -> Data {
        var body = BinaryWriter()
        if let icc = Self.iccData(for: image.space) {
            body.ascii("8BIM")
            body.u16(Self.iccResourceID)
            body.u8(0); body.u8(0)
            body.u32(UInt32(icc.count))
            body.bytes(icc)
            if icc.count % 2 != 0 { body.u8(0) }
        }
        body.ascii("8BIM")
        body.u16(Self.resolutionResourceID)
        body.u8(0); body.u8(0)
        body.u32(16)
        let fixed = UInt32((max(0, image.dpi) * 65536).rounded())
        body.u32(fixed)
        body.u16(1); body.u16(1)
        body.u32(fixed)
        body.u16(1); body.u16(1)

        var out = BinaryWriter()
        out.u32(UInt32(body.data.count))
        out.raw(body.data)
        return out.data
    }

    private func parseImageResources(_ r: inout BinaryReader, length: Int) throws -> (space: WorkingSpace, dpi: Double) {
        let end = r.offset + length
        var space: WorkingSpace = .sRGB
        var dpi: Double = 72
        while r.offset + 12 <= end {
            guard (try? r.ascii(4)) == "8BIM" else { break }
            let id = try r.u16()
            let nameLen = Int(try r.u8())
            try r.skip(nameLen)
            if (1 + nameLen) % 2 != 0 { try r.skip(1) }
            let dataLen = Int(try r.u32())
            let data = try r.bytes(dataLen)
            if dataLen % 2 != 0 { try r.skip(1) }
            if id == Self.iccResourceID { space = Self.classifyICC(data) }
            else if id == Self.resolutionResourceID, data.count >= 4 {
                let fixed = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
                let v = Double(fixed) / 65536.0
                if v > 0 { dpi = v }
            }
        }
        if r.offset < end { try r.skip(end - r.offset) }
        return (space, dpi)
    }

    nonisolated static func iccData(for space: WorkingSpace) -> [UInt8]? {
        guard let d = space.cgColorSpace.copyICCData() as Data? else { return nil }
        return [UInt8](d)
    }

    nonisolated static func classifyICC(_ data: [UInt8]) -> WorkingSpace {
        if let p3 = iccData(for: .displayP3), p3 == data { return .displayP3 }
        return .sRGB
    }

    private static let lsctOpen: UInt32 = 1
    private static let lsctClosed: UInt32 = 2
    private static let lsctBounding: UInt32 = 3

    private static func lsctBlock(_ divider: SectionDivider) -> Data {
        let type: UInt32
        switch divider {
        case .none:     return Data()
        case .open:     type = lsctOpen
        case .closed:   type = lsctClosed
        case .bounding: type = lsctBounding
        }
        var w = BinaryWriter()
        w.ascii("8BIM")
        w.ascii("lsct")
        w.u32(4)
        w.u32(type)
        return w.data
    }

    private static func parseSectionDivider(_ b: [UInt8]) -> SectionDivider {
        let sig = Array("8BIM".utf8), key = Array("lsct".utf8)
        var i = 0
        while i + 16 <= b.count {
            if Array(b[i..<i+4]) == sig, Array(b[i+4..<i+8]) == key {
                let d = i + 12
                let type = (UInt32(b[d]) << 24) | (UInt32(b[d+1]) << 16) | (UInt32(b[d+2]) << 8) | UInt32(b[d+3])
                switch type {
                case lsctBounding: return .bounding
                case lsctOpen:     return .open
                case lsctClosed:   return .closed
                default:           return .none
                }
            }
            i += 1
        }
        return .none
    }

    private static func pascalName(_ name: String) -> [UInt8] {
        let chars = Array(name.utf8.prefix(255))
        var block: [UInt8] = [UInt8(chars.count)] + chars
        while block.count % 4 != 0 { block.append(0) }
        return block
    }

    // MARK: - Decode

    func decode(_ data: Data) throws -> CanvasImage {
        var r = BinaryReader(data)

        guard try r.ascii(4) == "8BPS" else { throw CodecError.malformed("bad signature") }
        let version = try r.u16()
        guard version == 1 else { throw CodecError.unsupported("PSB/version \(version)") }
        try r.skip(6)
        let channels = Int(try r.u16())
        let height = Int(try r.u32())
        let width = Int(try r.u32())
        let depth = try r.u16()
        let colorMode = try r.u16()
        guard width > 0, height > 0,
              width <= Self.maxDimension, height <= Self.maxDimension else {
            throw CodecError.malformed("invalid dimensions \(width)x\(height)")
        }
        guard depth == 8 || depth == 16 else { throw CodecError.unsupported("\(depth)-bit depth") }
        guard colorMode == 3 else { throw CodecError.unsupported("colour mode \(colorMode) (only RGB)") }
        let bps = depth == 16 ? 2 : 1

        let colorModeLen = Int(try r.u32()); try r.skip(colorModeLen)
        let resourcesLen = Int(try r.u32())
        let (space, dpi) = try parseImageResources(&r, length: resourcesLen)

        let layerMaskLen = Int(try r.u32())
        var layers: [LayerImage] = []
        if layerMaskLen > 0 {
            let sectionStart = r.offset
            layers = try decodeLayers(&r, width: width, height: height, bps: bps)
            let consumed = r.offset - sectionStart
            if consumed < layerMaskLen { try r.skip(layerMaskLen - consumed) }
        }

        if layers.isEmpty {
            let merged = try decodeMergedImage(&r, width: width, height: height, channels: channels, bps: bps)
            layers = [LayerImage(name: "Background", isVisible: true, opacity: 1,
                                 blendMode: .normal, pixels: merged)]
        }

        return CanvasImage(fileName: "Untitled", width: width, height: height, layers: layers,
                           depth: depth == 16 ? .sixteen : .eight, space: space, dpi: dpi)
    }

    private func decodeLayers(_ r: inout BinaryReader, width: Int, height: Int, bps: Int) throws -> [LayerImage] {
        let layerInfoLen = Int(try r.u32())
        guard layerInfoLen > 0 else { return [] }
        let layerInfoStart = r.offset

        var count = Int(try r.i16())
        if count < 0 { count = -count }

        struct LayerMeta {
            var top: Int, left: Int, bottom: Int, right: Int
            var channels: [(id: Int16, length: Int)]
            var opacity: Float
            var visible: Bool
            var name: String
            var blendMode: BlendMode
            var divider: SectionDivider
            var maskRect: (top: Int, left: Int, w: Int, h: Int)?
            var maskDisabled: Bool
        }
        var metas: [LayerMeta] = []

        for _ in 0..<count {
            let top = Int(try r.i32()), left = Int(try r.i32())
            let bottom = Int(try r.i32()), right = Int(try r.i32())
            let nch = Int(try r.u16())
            var chans: [(Int16, Int)] = []
            for _ in 0..<nch {
                let id = try r.i16()
                let len = Int(try r.u32())
                chans.append((id, len))
            }
            guard try r.ascii(4) == "8BIM" else { throw CodecError.malformed("bad layer blend sig") }
            let blendKey = try r.ascii(4)
            let blendMode = Self.blendMode(fromPSDKey: blendKey)
            let opacity = Float(try r.u8()) / 255
            _ = try r.u8()
            let flags = try r.u8()
            _ = try r.u8()
            let visible = (flags & 0x02) == 0

            let extraLen = Int(try r.u32())
            let extraStart = r.offset
            let maskLen = Int(try r.u32())
            var maskRect: (top: Int, left: Int, w: Int, h: Int)? = nil
            var maskDisabled = false
            if maskLen >= 18 {
                let mtop = Int(try r.i32()), mleft = Int(try r.i32())
                let mbottom = Int(try r.i32()), mright = Int(try r.i32())
                _ = try r.u8()
                let mflags = try r.u8()
                maskDisabled = (mflags & 0x02) != 0
                if maskLen > 18 { try r.skip(maskLen - 18) }
                maskRect = (mtop, mleft, max(0, mright - mleft), max(0, mbottom - mtop))
            } else {
                try r.skip(maskLen)
            }
            let rangesLen = Int(try r.u32()); try r.skip(rangesLen)
            let nameLen = Int(try r.u8())
            let nameBytes = try r.bytes(nameLen)
            let nameFieldTotal = 1 + nameLen
            let pad = (4 - (nameFieldTotal % 4)) % 4
            try r.skip(pad)
            let name = String(bytes: nameBytes, encoding: .utf8) ?? "Layer"
            var divider: SectionDivider = .none
            let afterName = r.offset - extraStart
            if extraLen > afterName {
                let extra = try r.bytes(extraLen - afterName)
                divider = Self.parseSectionDivider(extra)
            }

            metas.append(LayerMeta(top: top, left: left, bottom: bottom, right: right,
                                   channels: chans, opacity: opacity, visible: visible,
                                   name: name, blendMode: blendMode, divider: divider,
                                   maskRect: maskRect, maskDisabled: maskDisabled))
        }

        var layers: [LayerImage] = []
        for meta in metas {
            let lw = max(0, meta.right - meta.left)
            let lh = max(0, meta.bottom - meta.top)
            var planes: [Int16: [UInt8]] = [:]
            for ch in meta.channels {
                let cw: Int, chh: Int
                if ch.id == Self.idMask, let mr = meta.maskRect { cw = mr.w; chh = mr.h } else { cw = lw; chh = lh }
                let plane = try readChannel(&r, declaredLength: ch.length, width: cw, height: chh, bps: bps)
                planes[ch.id] = plane
            }
            layers.append({
                var li = composeLayer(meta: (meta.top, meta.left, lw, lh, meta.opacity, meta.visible, meta.name),
                                      blendMode: meta.blendMode,
                                      planes: planes, canvasW: width, canvasH: height, bps: bps)
                li.divider = meta.divider
                if let mp = planes[Self.idMask], let mr = meta.maskRect {
                    li.maskPixels = Self.composeMaskPlane(mp, rect: mr, canvasW: width, canvasH: height, bps: bps)
                    li.maskEnabled = !meta.maskDisabled
                }
                return li
            }())
        }

        let consumed = r.offset - layerInfoStart
        if consumed < layerInfoLen { try r.skip(layerInfoLen - consumed) }
        return layers
    }

    private func readChannel(_ r: inout BinaryReader, declaredLength: Int, width: Int, height: Int, bps: Int) throws -> [UInt8] {
        let rowBytes = max(0, width * bps)
        let total = max(0, width * height * bps)
        guard declaredLength >= 2 else { return [UInt8](repeating: 0, count: total) }
        let compression = try r.u16()
        switch compression {
        case 0:
            return try r.bytes(total)
        case 1:
            var counts: [Int] = []; counts.reserveCapacity(height)
            for _ in 0..<height { counts.append(Int(try r.u16())) }
            var out = [UInt8](); out.reserveCapacity(total)
            for rowCount in counts {
                let packed = try r.bytes(rowCount)
                out.append(contentsOf: Self.unpackBits(packed, expected: rowBytes))
            }
            return out
        default:
            throw CodecError.unsupported("channel compression \(compression)")
        }
    }

    private func decodeMergedImage(_ r: inout BinaryReader, width: Int, height: Int, channels: Int, bps: Int) throws -> [UInt8] {
        let pixelCount = width * height
        let planeBytes = pixelCount * bps
        guard r.remaining > 0, pixelCount > 0 else {
            return [UInt8](repeating: 0, count: pixelCount * 4 * bps)
        }
        let compression = try r.u16()
        var planes: [[UInt8]] = []
        switch compression {
        case 0:
            for _ in 0..<channels { planes.append(try r.bytes(planeBytes)) }
        case 1:
            var counts: [Int] = []
            for _ in 0..<(channels * height) { counts.append(Int(try r.u16())) }
            var idx = 0
            for _ in 0..<channels {
                var plane = [UInt8](); plane.reserveCapacity(planeBytes)
                for _ in 0..<height {
                    let packed = try r.bytes(counts[idx]); idx += 1
                    plane.append(contentsOf: Self.unpackBits(packed, expected: width * bps))
                }
                planes.append(plane)
            }
        default:
            throw CodecError.unsupported("composite compression \(compression)")
        }

        var rgba = [UInt8](repeating: 0, count: pixelCount * 4 * bps)
        for i in 0..<pixelCount {
            for ch in 0..<4 {
                let plane = ch < planes.count ? planes[ch] : nil
                placeSample(from: plane, srcIndex: i, into: &rgba, dstPixel: i, channel: ch, bps: bps,
                            defaultOpaqueAlpha: ch == 3)
            }
        }
        return rgba
    }

    private func composeLayer(meta: (top: Int, left: Int, w: Int, h: Int, opacity: Float, visible: Bool, name: String),
                              blendMode: BlendMode,
                              planes: [Int16: [UInt8]],
                              canvasW: Int, canvasH: Int, bps: Int) -> LayerImage {
        var pixels = [UInt8](repeating: 0, count: canvasW * canvasH * 4 * bps)
        let red = planes[Self.idRed], green = planes[Self.idGreen]
        let blue = planes[Self.idBlue], alpha = planes[Self.idAlpha]

        for y in 0..<meta.h {
            let cy = meta.top + y
            if cy < 0 || cy >= canvasH { continue }
            for x in 0..<meta.w {
                let cx = meta.left + x
                if cx < 0 || cx >= canvasW { continue }
                let si = y * meta.w + x
                let di = cy * canvasW + cx
                placeSample(from: red,   srcIndex: si, into: &pixels, dstPixel: di, channel: 0, bps: bps, defaultOpaqueAlpha: false)
                placeSample(from: green, srcIndex: si, into: &pixels, dstPixel: di, channel: 1, bps: bps, defaultOpaqueAlpha: false)
                placeSample(from: blue,  srcIndex: si, into: &pixels, dstPixel: di, channel: 2, bps: bps, defaultOpaqueAlpha: false)
                placeSample(from: alpha, srcIndex: si, into: &pixels, dstPixel: di, channel: 3, bps: bps, defaultOpaqueAlpha: true)
            }
        }

        return LayerImage(name: meta.name, isVisible: meta.visible, opacity: meta.opacity,
                          blendMode: blendMode, pixels: pixels)
    }

    private static func composeMaskPlane(_ plane: [UInt8], rect: (top: Int, left: Int, w: Int, h: Int),
                                         canvasW: Int, canvasH: Int, bps: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: canvasW * canvasH * bps)
        for y in 0..<rect.h {
            let cy = rect.top + y
            if cy < 0 || cy >= canvasH { continue }
            for x in 0..<rect.w {
                let cx = rect.left + x
                if cx < 0 || cx >= canvasW { continue }
                let si = y * rect.w + x, di = cy * canvasW + cx
                if bps == 1 {
                    out[di] = si < plane.count ? plane[si] : 0
                } else {
                    let so = si * 2, dof = di * 2
                    if so + 1 < plane.count { out[dof] = plane[so + 1]; out[dof + 1] = plane[so] }
                }
            }
        }
        return out
    }

    private func placeSample(from plane: [UInt8]?, srcIndex: Int, into out: inout [UInt8],
                             dstPixel: Int, channel: Int, bps: Int, defaultOpaqueAlpha: Bool) {
        if bps == 1 {
            let v: UInt8
            if let plane, srcIndex < plane.count { v = plane[srcIndex] } else { v = defaultOpaqueAlpha ? 255 : 0 }
            out[dstPixel * 4 + channel] = v
        } else {
            let o = (dstPixel * 4 + channel) * 2
            if let plane, srcIndex * 2 + 1 < plane.count {
                out[o] = plane[srcIndex * 2 + 1]; out[o + 1] = plane[srcIndex * 2]
            } else {
                let v: UInt16 = defaultOpaqueAlpha ? 65535 : 0
                out[o] = UInt8(v & 0xff); out[o + 1] = UInt8(v >> 8)
            }
        }
    }

    private static func unpackBits(_ input: [UInt8], expected: Int) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(expected)
        var i = 0
        while i < input.count && out.count < expected {
            let n = Int8(bitPattern: input[i]); i += 1
            if n >= 0 {
                let runLength = Int(n) + 1
                for _ in 0..<runLength where i < input.count { out.append(input[i]); i += 1 }
            } else if n != -128 {
                let runLength = 1 - Int(n)
                if i < input.count {
                    let byte = input[i]; i += 1
                    for _ in 0..<runLength { out.append(byte) }
                }
            }
        }
        if out.count < expected { out.append(contentsOf: [UInt8](repeating: 0, count: expected - out.count)) }
        if out.count > expected { out.removeLast(out.count - expected) }
        return out
    }
}
