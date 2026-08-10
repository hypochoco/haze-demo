//
//  BlendMode.swift
//  Haze — model
//

enum BlendMode: String, Codable, CaseIterable {
    case normal
    case multiply
    case screen

    var displayName: String {
        switch self {
        case .normal:   return "Normal"
        case .multiply: return "Multiply"
        case .screen:   return "Screen"
        }
    }

    var gpuCode: UInt32 {
        switch self {
        case .normal:   return 0
        case .multiply: return 1
        case .screen:   return 2
        }
    }

    var isNormal: Bool { self == .normal }
}
