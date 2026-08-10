//
//  PixelPayload.swift
//  Haze — history
//

import Foundation

struct PixelPayload {
    private let storage: Data
    private let isCompressed: Bool
    let rawCount: Int

    init(raw: [UInt8]) {
        rawCount = raw.count
        if raw.count > 64,
           let c = try? (Data(raw) as NSData).compressed(using: .lz4) as Data,
           c.count < raw.count {
            storage = c
            isCompressed = true
        } else {
            storage = Data(raw)
            isCompressed = false
        }
    }

    var byteCount: Int { storage.count }

    func raw() -> [UInt8] {
        if isCompressed, let d = try? (storage as NSData).decompressed(using: .lz4) as Data {
            return [UInt8](d)
        }
        return [UInt8](storage)
    }
}
