//
//  ChatIntelligence.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligence: Equatable {
    var messages: [ChatMessage]
    var suggestedAction: String
    var reasoning: String
}
