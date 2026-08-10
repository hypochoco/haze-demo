//
//  BrushSettings.swift
//  Haze — tools
//

import Foundation
import simd

struct BrushSettings: Equatable, Codable {
    var size: Float = 24
    var hardness: Float = 0.8
    var spacing: Float = 0.1
    var color: SIMD4<Float> = [0, 0, 0, 1]
    var opacity: Float = 1
    var flow: Float = 1

    var pressureSize: Float = 0
    var pressureFlow: Float = 0
    var pressureOpacity: Float = 0

    // MARK: - Tip shape (textured stamps + shape dynamics)

    var tipID: UUID? = nil
    var angle: Float = 0
    var roundness: Float = 1
    var angleFollowsDirection: Bool = false
    var angleJitter: Float = 0
    var sizeJitter: Float = 0
    var scatter: Float = 0

    var radius: Float { size / 2 }
    var spacingPx: Float { max(1, spacing * size) }
    var angleRadians: Float { angle * .pi / 180 }

    // MARK: - Presets (shape/dynamics only — colour is not part of a preset)

    static let presetColor: SIMD4<Float> = [0, 0, 0, 1]

    func presetFields() -> BrushSettings {
        var c = self; c.color = Self.presetColor; return c
    }

    func applying(preset p: BrushSettings) -> BrushSettings {
        var out = p; out.color = self.color; return out
    }

    func equalsIgnoringColor(_ other: BrushSettings) -> Bool {
        presetFields() == other.presetFields()
    }
}

extension BrushSettings {
    private enum CodingKeys: String, CodingKey {
        case size, hardness, spacing, color, opacity, flow, pressureSize, pressureFlow, pressureOpacity
        case tipID, angle, roundness, angleFollowsDirection, angleJitter, sizeJitter, scatter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrushSettings()
        self.size            = try c.decodeIfPresent(Float.self, forKey: .size) ?? d.size
        self.hardness        = try c.decodeIfPresent(Float.self, forKey: .hardness) ?? d.hardness
        self.spacing         = try c.decodeIfPresent(Float.self, forKey: .spacing) ?? d.spacing
        self.color           = try c.decodeIfPresent(SIMD4<Float>.self, forKey: .color) ?? d.color
        self.opacity         = try c.decodeIfPresent(Float.self, forKey: .opacity) ?? d.opacity
        self.flow            = try c.decodeIfPresent(Float.self, forKey: .flow) ?? d.flow
        self.pressureSize    = try c.decodeIfPresent(Float.self, forKey: .pressureSize) ?? d.pressureSize
        self.pressureFlow    = try c.decodeIfPresent(Float.self, forKey: .pressureFlow) ?? d.pressureFlow
        self.pressureOpacity = try c.decodeIfPresent(Float.self, forKey: .pressureOpacity) ?? d.pressureOpacity
        self.tipID                = try c.decodeIfPresent(UUID.self, forKey: .tipID) ?? d.tipID
        self.angle                = try c.decodeIfPresent(Float.self, forKey: .angle) ?? d.angle
        self.roundness            = try c.decodeIfPresent(Float.self, forKey: .roundness) ?? d.roundness
        self.angleFollowsDirection = try c.decodeIfPresent(Bool.self, forKey: .angleFollowsDirection) ?? d.angleFollowsDirection
        self.angleJitter          = try c.decodeIfPresent(Float.self, forKey: .angleJitter) ?? d.angleJitter
        self.sizeJitter           = try c.decodeIfPresent(Float.self, forKey: .sizeJitter) ?? d.sizeJitter
        self.scatter              = try c.decodeIfPresent(Float.self, forKey: .scatter) ?? d.scatter
    }
}
