//
//  FuzzyMatch.swift
//  Haze — views/shared
//

import Foundation

enum FuzzyMatch {
    static func score(_ query: String, _ candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query)
        let qLower = Array(query.lowercased())
        let c = Array(candidate)
        let cLower = Array(candidate.lowercased())

        var qi = 0
        var score = 0
        var lastMatch = -2
        for ci in 0..<cLower.count where qi < qLower.count {
            guard cLower[ci] == qLower[qi] else { continue }
            var s = 10
            if ci == lastMatch + 1 { s += 15 }
            if ci == 0 { s += 20 }
            else {
                let prev = c[ci - 1]
                if !prev.isLetter && !prev.isNumber { s += 15 }
                else if prev.isLowercase && c[ci].isUppercase { s += 10 }
            }
            if c[ci] == q[qi] { s += 2 }
            s -= min(ci, 10)
            score += s
            lastMatch = ci
            qi += 1
        }
        return qi == qLower.count ? score : nil
    }
}
