//
//  BinaryIO.swift
//  Haze — io
//

import Foundation

struct BinaryWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) {
        data.append(UInt8(v >> 8)); data.append(UInt8(v & 0xff))
    }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) {
        data.append(UInt8((v >> 24) & 0xff))
        data.append(UInt8((v >> 16) & 0xff))
        data.append(UInt8((v >> 8) & 0xff))
        data.append(UInt8(v & 0xff))
    }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func raw(_ d: Data) { data.append(d) }
    mutating func zeros(_ n: Int) { data.append(contentsOf: [UInt8](repeating: 0, count: n)) }
}

struct BinaryReader {
    private let data: [UInt8]
    private(set) var offset: Int = 0

    init(_ data: Data) { self.data = [UInt8](data) }

    var remaining: Int { data.count - offset }

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw CodecError.malformed("unexpected EOF") }
        defer { offset += 1 }
        return data[offset]
    }
    mutating func u16() throws -> UInt16 {
        let hi = UInt16(try u8()), lo = UInt16(try u8())
        return (hi << 8) | lo
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u32() throws -> UInt32 {
        let a = UInt32(try u8()), b = UInt32(try u8()), c = UInt32(try u8()), d = UInt32(try u8())
        return (a << 24) | (b << 16) | (c << 8) | d
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func ascii(_ n: Int) throws -> String {
        let b = try bytes(n)
        return String(bytes: b, encoding: .ascii) ?? ""
    }
    mutating func bytes(_ n: Int) throws -> [UInt8] {
        guard offset + n <= data.count else { throw CodecError.malformed("unexpected EOF") }
        defer { offset += n }
        return Array(data[offset..<offset + n])
    }
    mutating func skip(_ n: Int) throws {
        guard offset + n <= data.count else { throw CodecError.malformed("skip past EOF") }
        offset += n
    }
}
