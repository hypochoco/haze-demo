//
//  Log.swift
//  Haze — diagnostics
//

import OSLog

enum Log {
    static let subsystem = "com.hypochoco.Haze"

    static let app     = Logger(subsystem: subsystem, category: "app")
    static let render  = Logger(subsystem: subsystem, category: "render")
    static let input   = Logger(subsystem: subsystem, category: "input")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let gpu     = Logger(subsystem: subsystem, category: "gpu")

    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    @discardableResult
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
