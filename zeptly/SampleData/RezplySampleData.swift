//
//  RezplySampleData.swift
//  zeptly
//

import SwiftUI

enum RezplySampleData {
    static let chats: [Chat] = [
        Chat(
            id: "sarah-jenkins",
            name: "Sarah Jenkins",
            timeLabel: "10:42 AM",
            preview: "The new proposal direction looks strong. Let's align on the final tone.",
            chipTitle: "Warm Persona",
            chipSymbol: "heart.text.square",
            avatarSymbol: nil,
            initials: "SJ",
            gradient: [RezplyColor.peach, RezplyColor.primaryContainer],
            isUnread: true,
            isOnline: true,
            contactContext: ContactContext(
                relationshipSubtitle: "Key Client & Collaborative Partner",
                relationshipNotes: "",
                keyFacts: [
                    "Lives in Seattle",
                    "Prefers morning meetings",
                    "Dog named 'Baxter'"
                ],
                currentInteractionGoal: "Close Q3 proposal with clear next steps",
                preferredPersona: "Warm & Collaborative"
            )
        ),
        Chat(
            id: "marcus-vance",
            name: "Marcus Vance",
            timeLabel: "Yesterday",
            preview: "Thanks for sending over the quarterly reports. I added notes.",
            chipTitle: "Professional Persona",
            chipSymbol: "briefcase",
            avatarSymbol: nil,
            initials: "MV",
            gradient: [RezplyColor.deepNavy, RezplyColor.surfaceDim],
            isUnread: false,
            isOnline: false,
            contactContext: ContactContext(
                relationshipSubtitle: "Finance Lead & Detail-Oriented Reviewer",
                relationshipNotes: "Marcus values concise summaries backed by numbers. He usually wants risks called out before recommendations.",
                keyFacts: [
                    "Reviews reports on Tuesdays",
                    "Prefers bullet summaries",
                    "Asks for source links"
                ],
                currentInteractionGoal: "Confirm quarterly report revisions",
                preferredPersona: "Professional"
            )
        ),
        Chat(
            id: "project-aurora-team",
            name: "Project Aurora Team",
            timeLabel: "Tuesday",
            preview: "Sarah: We need to finalize the launch timeline.",
            chipTitle: "General",
            chipSymbol: "number",
            avatarSymbol: "person.2",
            initials: "PA",
            gradient: [RezplyColor.surfaceVariant, RezplyColor.secondaryContainer],
            isUnread: false,
            isOnline: false,
            contactContext: nil
        ),
        Chat(
            id: "nadia-chen",
            name: "Nadia Chen",
            timeLabel: "Mon",
            preview: "Can you soften the reply and keep the core ask clear?",
            chipTitle: "Creative Persona",
            chipSymbol: "sparkles",
            avatarSymbol: nil,
            initials: "NC",
            gradient: [RezplyColor.secondaryContainer, RezplyColor.peach],
            isUnread: false,
            isOnline: true,
            contactContext: ContactContext(
                relationshipSubtitle: "Creative Partner & Brand Collaborator",
                relationshipNotes: "Nadia responds well to expressive options, especially when the final ask stays crisp and easy to act on.",
                keyFacts: [
                    "Likes three options",
                    "Prefers visual language",
                    "Usually replies after lunch"
                ],
                currentInteractionGoal: "Polish launch copy without losing clarity",
                preferredPersona: "Creative"
            )
        ),
        Chat(
            id: "ops-review",
            name: "Ops Review",
            timeLabel: "Fri",
            preview: "Draft is ready. Please check the summary before noon.",
            chipTitle: "Professional Persona",
            chipSymbol: "briefcase",
            avatarSymbol: "chart.bar.doc.horizontal",
            initials: "OR",
            gradient: [RezplyColor.surfaceVariant, RezplyColor.primaryFixed],
            isUnread: false,
            isOnline: false,
            contactContext: nil
        ),
        Chat(
            id: "mika-patel",
            name: "Mika Patel",
            timeLabel: "Thu",
            preview: "Perfect, send the short version with one friendly note.",
            chipTitle: "Minimalist",
            chipSymbol: "text.alignleft",
            avatarSymbol: nil,
            initials: "MP",
            gradient: [RezplyColor.primaryContainer, RezplyColor.deepNavy],
            isUnread: false,
            isOnline: false,
            contactContext: ContactContext(
                relationshipSubtitle: "Fast-Moving Teammate & Clear Communicator",
                relationshipNotes: "Mika prefers short replies with one friendly sentence up front, then the action item.",
                keyFacts: [
                    "Prefers brief replies",
                    "Skims on mobile",
                    "Likes clear deadlines"
                ],
                currentInteractionGoal: "Send concise follow-up by end of day",
                preferredPersona: "Minimalist"
            )
        ),
        Chat(
            id: "launch-room",
            name: "Launch Room",
            timeLabel: "Wed",
            preview: "Alex: I moved the copy review to tomorrow morning.",
            chipTitle: "General",
            chipSymbol: "number",
            avatarSymbol: "person.3",
            initials: "LR",
            gradient: [RezplyColor.surfaceContainerHigh, RezplyColor.secondaryContainer],
            isUnread: false,
            isOnline: false,
            contactContext: nil
        )
    ]

    static let chatIntelligenceByID: [String: ChatIntelligence] = [
        "sarah-jenkins": ChatIntelligence(
            contextChips: ["Brief updates", "Schedule Q3 Review", "Professional"],
            messages: [
                ChatMessage(sender: .contact, text: "Hey, are we still doing that long sync?", timeLabel: "10:42 AM"),
                ChatMessage(sender: .user, text: "I think we can condense it. I have the initial Q3 numbers.", timeLabel: "10:45 AM"),
                ChatMessage(
                    sender: .contact,
                    text: "Great. I prefer keeping these updates brief if possible. Just send over the highlights and let's figure out when to do the actual formal review.",
                    timeLabel: "10:46 AM"
                ),
                ChatMessage(sender: .user, text: "That works. I can send a compact update today.", timeLabel: "10:48 AM"),
                ChatMessage(sender: .contact, text: "Perfect. Please include a suggested time for the formal review too.", timeLabel: "10:50 AM")
            ],
            suggestedReplies: [
                SuggestedReply(
                    text: "Hi Sarah, here is a quick update on the Q3 figures. Let's schedule a brief 15-minute review next Tuesday to align on the final steps. Please let me know your availability."
                ),
                SuggestedReply(
                    text: "Thanks for the overview. Given your preference for brief updates, I've summarized the key points below. I'd like to propose we formally review the Q3 strategy next week. Does Wednesday morning work?"
                )
            ],
            suggestedAction: "Send a concise summary first, then propose one specific review window instead of asking an open-ended scheduling question.",
            reasoning: "Sarah's historical pattern favors concise, actionable messages. The suggested replies prioritize immediate next steps while maintaining a professional distance appropriate for this project phase."
        ),
        "marcus-vance": ChatIntelligence(
            contextChips: ["Risk first", "Quarterly report", "Professional"],
            messages: [
                ChatMessage(sender: .contact, text: "Thanks for sending over the quarterly reports. I added notes.", timeLabel: "Yesterday"),
                ChatMessage(sender: .user, text: "Great, I'll review them and tighten the summary.", timeLabel: "Yesterday"),
                ChatMessage(sender: .contact, text: "Please call out the risks before the recommendation. That will make the review easier.", timeLabel: "Yesterday")
            ],
            suggestedReplies: [
                SuggestedReply(text: "Thanks Marcus. I'll lead with the key risks, then include the recommendation and supporting numbers underneath so the review path is clear."),
                SuggestedReply(text: "Got it. I'll revise the report so the risk summary comes first, followed by the source-backed recommendation.")
            ],
            suggestedAction: "Update the report structure before replying, then mention the exact order Marcus asked for.",
            reasoning: "Marcus tends to value auditability and decision clarity. A strong reply should acknowledge the requested structure and reduce back-and-forth."
        ),
        "nadia-chen": ChatIntelligence(
            contextChips: ["Soft tone", "Launch copy", "Creative"],
            messages: [
                ChatMessage(sender: .contact, text: "Can you soften the reply and keep the core ask clear?", timeLabel: "Mon"),
                ChatMessage(sender: .user, text: "Yes, I can make it feel warmer without losing the deadline.", timeLabel: "Mon"),
                ChatMessage(sender: .contact, text: "Exactly. Friendly, but still easy to act on.", timeLabel: "Mon")
            ],
            suggestedReplies: [
                SuggestedReply(text: "Absolutely. I'll soften the opening, keep the request direct, and make the deadline feel collaborative rather than abrupt."),
                SuggestedReply(text: "Yes. I'll make the tone warmer while preserving the main ask and the action needed from the team.")
            ],
            suggestedAction: "Offer Nadia two tone options after the first revision.",
            reasoning: "Nadia responds well to expressive options, but she still wants the request to stay crisp. A reply that promises warmth plus clarity should fit her style."
        )
    ]

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

    static let providers: [ProviderConnection] = [
        ProviderConnection(
            name: "OpenAI",
            model: "gpt-4-turbo",
            symbolName: "waveform",
            lastSynced: "Just now",
            isEnabled: true
        ),
        ProviderConnection(
            name: "Anthropic",
            model: "claude-3-opus",
            symbolName: "brain.head.profile",
            lastSynced: "2 hours ago",
            isEnabled: true
        )
    ]

    static var initialContactContexts: [String: ContactContext] {
        Dictionary(
            uniqueKeysWithValues: chats.compactMap { chat in
                guard let contactContext = chat.contactContext else {
                    return nil
                }
                return (chat.id, contactContext)
            }
        )
    }

    static func chat(withID id: String) -> Chat? {
        chats.first { $0.id == id }
    }

    static func chatIntelligence(withID id: String) -> ChatIntelligence {
        if let intelligence = chatIntelligenceByID[id] {
            return intelligence
        }

        return ChatIntelligence(
            contextChips: ["Recent context", "Reply support", "Chat Intel"],
            messages: [
                ChatMessage(sender: .contact, text: "Can you take a look when you have a moment?", timeLabel: "Recent"),
                ChatMessage(sender: .user, text: "Yes, I can review it and send a focused response.", timeLabel: "Recent")
            ],
            suggestedReplies: [
                SuggestedReply(text: "Thanks for the context. I'll review this and send back a clear next step shortly."),
                SuggestedReply(text: "Got it. I'll take a look and follow up with the most important points first.")
            ],
            suggestedAction: "Ask one clarifying question only if the next step is still ambiguous.",
            reasoning: "There is limited saved context for this chat, so the safest recommendation is concise and low-commitment while still moving the exchange forward."
        )
    }
}
