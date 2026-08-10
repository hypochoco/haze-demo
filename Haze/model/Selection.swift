//
//  Selection.swift
//  Haze — model
//

import simd
import AppKit

enum SelectionOp: String, Equatable {
    case replace, add, subtract, intersect

    init(_ flags: NSEvent.ModifierFlags) {
        let shift = flags.contains(.shift), option = flags.contains(.option)
        switch (shift, option) {
        case (true, true):   self = .intersect
        case (true, false):  self = .add
        case (false, true):  self = .subtract
        default:             self = .replace
        }
    }

    var title: String {
        switch self {
        case .replace:   return "Select"
        case .add:       return "Add to Selection"
        case .subtract:  return "Subtract from Selection"
        case .intersect: return "Intersect Selection"
        }
    }
}

struct SelectionState: Equatable {
    var isActive: Bool = false
    var bounds: PixelRect = PixelRect(x: 0, y: 0, width: 0, height: 0)
    var version: Int = 0
    var path: [[SIMD2<Float>]] = []

    static let none = SelectionState()
}
