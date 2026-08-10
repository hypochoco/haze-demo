//
//  IDs.swift
//  Haze — model
//

import Foundation

struct LayerID: Hashable, Codable {
    let raw: UUID
    init(_ raw: UUID = UUID()) { self.raw = raw }
}

struct CanvasID: Hashable, Codable {
    let raw: UUID
    init(_ raw: UUID = UUID()) { self.raw = raw }
}
