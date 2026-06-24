//
//  RezplyModels.swift
//  zeptly
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case personas = "Personas"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .inbox:
            "bubble.left"
        case .personas:
            "face.smiling"
        case .settings:
            "gearshape"
        }
    }
}

struct Conversation: Identifiable {
    let id: String
    let name: String
    let timeLabel: String
    let preview: String
    let chipTitle: String
    let chipSymbol: String
    let avatarSymbol: String?
    let initials: String
    let gradient: [Color]
    let isUnread: Bool
    let isOnline: Bool
    let contactContext: ContactContext?
}

struct ContactContext: Equatable {
    var relationshipSubtitle: String
    var relationshipNotes: String
    var keyFacts: [String]
    var currentInteractionGoal: String
    var preferredPersona: String

    static let empty = ContactContext(
        relationshipSubtitle: "",
        relationshipNotes: "",
        keyFacts: [],
        currentInteractionGoal: "",
        preferredPersona: "Professional"
    )
}

struct Persona: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let symbolName: String
    let accent: Color
    let tags: [String]
}

struct ProviderConnection: Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let symbolName: String
    let lastSynced: String
    var isEnabled: Bool
}

enum RezplySampleData {
    static let conversations: [Conversation] = [
        Conversation(
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
        Conversation(
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
        Conversation(
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
        Conversation(
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
        Conversation(
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
        Conversation(
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
        Conversation(
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
            uniqueKeysWithValues: conversations.compactMap { conversation in
                guard let contactContext = conversation.contactContext else {
                    return nil
                }
                return (conversation.id, contactContext)
            }
        )
    }

    static func conversation(withID id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }
}
