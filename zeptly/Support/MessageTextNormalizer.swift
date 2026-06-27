//
//  MessageTextNormalizer.swift
//  zeptly
//

import Foundation

enum MessageTextNormalizer {
    static func normalize(_ text: String) -> String {
        text
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}
