//
//  PerfCounters.swift
//  Haze — diagnostics
//

#if DEBUG
enum PerfCounters {
    static var composites = 0

    static func takeComposites() -> Int { defer { composites = 0 }; return composites }
}
#endif
