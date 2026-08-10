//
//  Notice.swift
//  Haze — notifications
//

import Foundation

enum NoticeSeverity: Equatable {
    case info, warning, error
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let severity: NoticeSeverity
}
