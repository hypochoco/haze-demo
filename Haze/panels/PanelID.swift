//
//  PanelID.swift
//  Haze — panels
//

struct PanelID: Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

extension PanelID {
    static let color = PanelID("color")
    static let brush = PanelID("brush")
    static let layers = PanelID("layers")
    static let gradient = PanelID("gradient")
    static let info  = PanelID("info")
    static let historyDebug = PanelID("historyDebug")
}
