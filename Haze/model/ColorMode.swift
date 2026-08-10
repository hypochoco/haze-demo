//
//  ColorMode.swift
//  Haze — model
//

import Metal
import CoreGraphics

enum PixelDepth: String, Codable, CaseIterable {
    case eight, sixteen

    var bytesPerPixel: Int { self == .eight ? 4 : 8 }
    var title: String { self == .eight ? "8-bit" : "16-bit" }
    var mtlPixelFormat: MTLPixelFormat { self == .eight ? .bgra8Unorm : .rgba16Unorm }
}

enum WorkingSpace: String, Codable, CaseIterable {
    case sRGB, displayP3

    var title: String { self == .sRGB ? "sRGB" : "Display P3" }
    nonisolated var cgColorSpace: CGColorSpace {
        let name: CFString = self == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
        return CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
    }
}

struct ColorMode: Equatable, Codable {
    var depth: PixelDepth = .eight
    var space: WorkingSpace = .sRGB

    var bytesPerPixel: Int { depth.bytesPerPixel }
    var mtlPixelFormat: MTLPixelFormat { depth.mtlPixelFormat }
    var cgColorSpace: CGColorSpace { space.cgColorSpace }

    nonisolated static let `default` = ColorMode(depth: .eight, space: .sRGB)
}

extension MTLPixelFormat {
    nonisolated var haze_bytesPerPixel: Int {
        switch self {
        case .rgba16Unorm, .rgba16Float: return 8
        default: return 4
        }
    }
}
