//
//  ChatIntelligence.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligence: Equatable {
    var contextChips: [String]
    var messages: [ChatMessage]
    var suggestedReplies: [SuggestedReply]
    var suggestedAction: String
    var reasoning: String
}
