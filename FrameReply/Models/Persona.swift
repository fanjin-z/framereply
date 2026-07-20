import Foundation
import SwiftUI

nonisolated enum BuiltInPersonaID: String, Codable, CaseIterable, Sendable {
    case professional
    case spark
    case thoughtful
}

nonisolated enum BuiltInObservationID: String, Codable, CaseIterable, Sendable {
    case polishedConversational
    case concise
    case clearDirect
    case noEmoji
    case casualConversational
    case warmAcknowledgment
    case lightPlayfulness
    case tactfulClarity
    case naturalDetail
    case occasionalEmoji
    case veryRelaxed
    case highlyFormal
    case restrainedNeutral
    case limitedWarmth
    case openWarmth
    case oneConciseSentence
    case fullerContext
    case detailedWithoutFiller
    case rareEmoji
    case frequentEmoji
    case expressiveEmoji

    var canonicalPromptText: String {
        switch self {
        case .polishedConversational:
            "Uses polished, complete phrasing while remaining conversational."
        case .concise: "Keeps replies concise and omits nonessential detail."
        case .clearDirect: "States the main point clearly and directly."
        case .noEmoji: "Does not use emoji."
        case .casualConversational: "Keeps wording casual and conversational."
        case .warmAcknowledgment: "Shows clear warmth and considerate acknowledgment."
        case .lightPlayfulness: "Allows light playfulness when it fits naturally."
        case .tactfulClarity: "Balances clarity with tact."
        case .naturalDetail: "Uses the amount of detail naturally required by the message."
        case .occasionalEmoji: "Uses an occasional emoji only when it fits the conversation."
        case .veryRelaxed: "Uses very relaxed, conversational wording and natural contractions."
        case .highlyFormal: "Uses highly polished, formal phrasing and avoids slang."
        case .restrainedNeutral: "Keeps emotional tone restrained and neutral."
        case .limitedWarmth: "Shows limited warmth while staying courteous."
        case .openWarmth: "Writes with open warmth and empathy without inventing feelings."
        case .oneConciseSentence: "Usually replies in one very concise sentence."
        case .fullerContext: "Usually gives fuller replies with useful context."
        case .detailedWithoutFiller: "Writes detailed replies while avoiding repetition and filler."
        case .rareEmoji: "Uses emoji rarely and only when it reads naturally."
        case .frequentEmoji: "Uses emoji fairly often when they fit the conversation."
        case .expressiveEmoji: "Uses expressive emoji naturally without cluttering the message."
        }
    }

    func localizedText(locale: Locale = .current) -> String {
        AppStrings.resolve(AppStrings.Persona.observation(for: self), locale: locale)
    }
}

nonisolated struct BuiltInPersonaDefinition: Sendable {
    let id: BuiltInPersonaID
    let symbolName: String
    let accentKey: String
    let canonicalInstructions: String
    let observationIDs: [BuiltInObservationID]

    func localizedName(locale: Locale = .current) -> String {
        AppStrings.resolve(AppStrings.Persona.name(for: id), locale: locale)
    }

    func localizedSummary(locale: Locale = .current) -> String {
        AppStrings.resolve(AppStrings.Persona.summary(for: id), locale: locale)
    }

    func localizedInstructions(locale: Locale = .current) -> String {
        AppStrings.resolve(AppStrings.Persona.instructions(for: id), locale: locale)
    }

    static func definition(for id: BuiltInPersonaID) -> Self {
        switch id {
        case .professional:
            .init(
                id: id, symbolName: "briefcase", accentKey: "primary",
                canonicalInstructions:
                    "Write clear, structured messages for professional and formal conversations. Be decisive and avoid filler.",
                observationIDs: [.polishedConversational, .concise, .clearDirect, .noEmoji])
        case .spark:
            .init(
                id: id, symbolName: "sparkles", accentKey: "peach",
                canonicalInstructions:
                    "Write genuine dating messages that read the room. Match the other person's emotional intensity and never force flirtation or over-escalate.",
                observationIDs: [
                    .casualConversational, .warmAcknowledgment, .concise, .lightPlayfulness
                ])
        case .thoughtful:
            .init(
                id: id, symbolName: "heart.text.square", accentKey: "secondary",
                canonicalInstructions:
                    "Write tactful messages for friends, family, and delicate moments. Acknowledge emotion without inventing feelings or becoming overly sentimental.",
                observationIDs: [
                    .warmAcknowledgment, .tactfulClarity, .naturalDetail, .occasionalEmoji
                ])
        }
    }
}

nonisolated enum PersonaObservationOrigin: String, Codable, Sendable {
    case seed
    case ai
    case user
}

nonisolated enum PersonaObservationStatus: String, Codable, Sendable {
    case active
    case superseded
    case archived
}

nonisolated struct PersonaObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var templateID: BuiltInObservationID? = nil
    var origin: PersonaObservationOrigin
    var isUserProtected: Bool
    var status: PersonaObservationStatus
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct PersonaPromptContext: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let instructions: String
    let observations: [PersonaObservation]
    let protectedTombstones: [PersonaObservation]
}

struct Persona: Identifiable, Equatable {
    let id: UUID
    var name: String
    var summary: String
    var symbolName: String
    var accentKey: String
    var instructions: String
    var learningEnabled: Bool
    var sampleCount: Int

    var accent: Color {
        switch accentKey {
        case "peach": FrameReplyColor.peach
        case "secondary": FrameReplyColor.secondary
        default: FrameReplyColor.primary
        }
    }
}

/// A creation-only convenience. Selections compile to text and are never persisted.
nonisolated struct PersonaQuickSetupDimension: Identifiable, Equatable, Sendable {
    let id: String
    let title: LocalizedStringResource
    let lowAnchor: LocalizedStringResource
    let highAnchor: LocalizedStringResource
    let labels: [LocalizedStringResource]
    let observations: [BuiltInObservationID?]

    func label(for selection: Int) -> LocalizedStringResource { labels[index(for: selection)] }
    func observation(for selection: Int) -> BuiltInObservationID? {
        observations[index(for: selection)]
    }

    private func index(for selection: Int) -> Int { min(4, max(0, selection + 2)) }
}

nonisolated enum PersonaQuickSetup {
    static let dimensions: [PersonaQuickSetupDimension] = [
        .init(
            id: "formality", title: "Formality", lowAnchor: "Casual", highAnchor: "Formal",
            labels: ["Very casual", "Casual", "Balanced", "Formal", "Very formal"],
            observations: [
                .veryRelaxed, .casualConversational, nil, .polishedConversational,
                .highlyFormal
            ]
        ),
        .init(
            id: "warmth", title: "Warmth", lowAnchor: "Reserved", highAnchor: "Warm",
            labels: ["Very reserved", "Reserved", "Balanced", "Warm", "Very warm"],
            observations: [
                .restrainedNeutral, .limitedWarmth, nil, .warmAcknowledgment, .openWarmth
            ]
        ),
        .init(
            id: "length", title: "Reply Length", lowAnchor: "Short", highAnchor: "Detailed",
            labels: ["Very short", "Short", "Balanced", "Detailed", "Very detailed"],
            observations: [
                .oneConciseSentence, .concise, nil, .fullerContext, .detailedWithoutFiller
            ]
        ),
        .init(
            id: "emoji", title: "Emoji", lowAnchor: "Fewer", highAnchor: "More",
            labels: ["No emoji", "Few emoji", "Occasional", "Frequent", "Expressive"],
            observations: [
                .noEmoji, .rareEmoji, nil, .frequentEmoji, .expressiveEmoji
            ]
        )
    ]

    static func compile(selections: [String: Int]) -> [BuiltInObservationID] {
        dimensions.compactMap { $0.observation(for: selections[$0.id] ?? 0) }
    }

    static func replacingQuickSetupObservations(
        in existing: [PersonaObservation],
        selections: [String: Int]
    ) -> [PersonaObservation] {
        existing.filter { $0.templateID == nil }
            + compile(selections: selections).map { templateID in
                PersonaObservation(
                    id: UUID(),
                    text: templateID.canonicalPromptText,
                    templateID: templateID,
                    origin: .seed,
                    isUserProtected: false,
                    status: .active,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
    }
}

nonisolated enum PersonaLimits {
    static let maximumActiveObservations = 20
}
