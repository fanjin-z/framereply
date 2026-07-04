//
//  RezplySampleData.swift
//  zeptly
//

import SwiftUI

enum RezplySampleData {
    static let personas: [Persona] = [
        Persona(
            title: "The Professional",
            summary: "Ideal for client communications, official emails, and structured reports.",
            symbolName: "briefcase",
            accent: RezplyColor.primary,
            tags: ["Concise", "Formal", "Objective"]
        ),
        Persona(
            title: "The Creative",
            summary: "Brainstorming, marketing copy, and engaging storytelling.",
            symbolName: "paintpalette",
            accent: RezplyColor.secondary,
            tags: ["Imaginative", "Expressive", "Warm"]
        ),
        Persona(
            title: "The Minimalist",
            summary: "Quick replies, direct answers, and cutting through the noise.",
            symbolName: "text.alignleft",
            accent: RezplyColor.onSurface,
            tags: ["Direct", "Simple", "Factual"]
        )
    ]

    static let providers: [ProviderConnection] = []

    static func chatIntelligence(withID _: String) -> ChatIntelligence {
        ChatIntelligence(
            contextChips: ["Recent context", "Reply support", "Chat Intel"],
            messages: [],
            suggestedAction: "Ask one clarifying question only if the next step is still ambiguous.",
            reasoning: "There is limited saved context for this chat, so the safest recommendation is concise and low-commitment while still moving the exchange forward."
        )
    }
}
