//
//  ToolKind.swift
//  Haze — tools
//

import Foundation

enum ToolKind: String, CaseIterable, Identifiable {
    case brush
    case eraser
    case eyedropper
    case lasso
    case polygonLasso
    case move
    case transform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brush:        return "Brush"
        case .eraser:       return "Eraser"
        case .eyedropper:   return "Eyedropper"
        case .lasso:        return "Lasso"
        case .polygonLasso: return "Polygon Lasso"
        case .move:         return "Move Selection"
        case .transform:    return "Free Transform"
        }
    }

    var systemImage: String {
        switch self {
        case .brush:        return "paintbrush.pointed.fill"
        case .eraser:       return "eraser.fill"
        case .eyedropper:   return "eyedropper"
        case .lasso:        return "lasso"
        case .polygonLasso: return "scribble"
        case .move:         return "arrow.up.and.down.and.arrow.left.and.right"
        case .transform:    return "crop.rotate"
        }
    }

    var isPaint: Bool { self == .brush || self == .eraser }
    var isSelection: Bool { self == .lasso || self == .polygonLasso }
}

extension ToolKind {
    var paintSlot: ToolKind { isPaint ? self : .brush }

    var defaultPaintSettings: BrushSettings { BrushSettings() }
}
