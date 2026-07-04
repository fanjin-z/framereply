//
//  ChatIntelligence.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligence: Equatable {
    var contextChips: [String]
    var messages: [ChatMessage]
    var suggestedAction: String
    var reasoning: String
}
