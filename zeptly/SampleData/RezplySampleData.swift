//
//  RezplySampleData.swift
//  zeptly
//

enum RezplySampleData {
    static let providers: [ProviderConnection] = []

    static func chatIntelligence(withID _: String) -> ChatIntelligence {
        ChatIntelligence(
            messages: [],
            suggestedAction: "Ask one clarifying question only if the next step is still ambiguous.",
            reasoning: "There is limited saved context for this chat, so the safest recommendation is concise and low-commitment while still moving the exchange forward."
        )
    }
}
