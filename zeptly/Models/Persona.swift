import Foundation
import SwiftUI

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

nonisolated enum PersonaObservationEvidenceSource: String, Codable, Sendable {
    case seed
    case messages
    case examples
    case user
}

nonisolated struct PersonaObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var origin: PersonaObservationOrigin
    var isUserProtected: Bool
    var status: PersonaObservationStatus
    var evidenceSource: PersonaObservationEvidenceSource
    var sourceMessageIDs: [UUID]
    var evidenceCount: Int
    var supersededByID: UUID?
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
    var lastLearnedAt: Date?

    var accent: Color {
        switch accentKey {
        case "peach": RezplyColor.peach
        case "secondary": RezplyColor.secondary
        default: RezplyColor.primary
        }
    }
}

/// A creation-only convenience. Selections compile to text and are never persisted.
nonisolated struct PersonaQuickSetupDimension: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let lowAnchor: String
    let highAnchor: String
    let labels: [String]
    let observations: [String?]

    func label(for selection: Int) -> String { labels[index(for: selection)] }
    func observation(for selection: Int) -> String? { observations[index(for: selection)] }

    private func index(for selection: Int) -> Int { min(4, max(0, selection + 2)) }
}

nonisolated enum PersonaQuickSetup {
    static let dimensions: [PersonaQuickSetupDimension] = [
        .init(
            id: "formality", title: "Formality", lowAnchor: "Casual", highAnchor: "Formal",
            labels: ["Very casual", "Casual", "Balanced", "Formal", "Very formal"],
            observations: [
                "Uses very relaxed, conversational wording and natural contractions.",
                "Keeps wording casual and conversational.", nil,
                "Uses polished, complete phrasing while remaining conversational.",
                "Uses highly polished, formal phrasing and avoids slang."
            ]
        ),
        .init(
            id: "warmth", title: "Warmth", lowAnchor: "Reserved", highAnchor: "Warm",
            labels: ["Very reserved", "Reserved", "Balanced", "Warm", "Very warm"],
            observations: [
                "Keeps emotional tone restrained and neutral.",
                "Shows limited warmth while staying courteous.", nil,
                "Shows clear warmth and considerate acknowledgment.",
                "Writes with open warmth and empathy without inventing feelings."
            ]
        ),
        .init(
            id: "length", title: "Reply Length", lowAnchor: "Short", highAnchor: "Detailed",
            labels: ["Very short", "Short", "Balanced", "Detailed", "Very detailed"],
            observations: [
                "Usually replies in one very concise sentence.",
                "Keeps replies concise and omits nonessential detail.", nil,
                "Usually gives fuller replies with useful context.",
                "Writes detailed replies while avoiding repetition and filler."
            ]
        ),
        .init(
            id: "emoji", title: "Emoji", lowAnchor: "Fewer", highAnchor: "More",
            labels: ["No emoji", "Few emoji", "Occasional", "Frequent", "Expressive"],
            observations: [
                "Does not use emoji.",
                "Uses emoji rarely and only when it reads naturally.", nil,
                "Uses emoji fairly often when they fit the conversation.",
                "Uses expressive emoji naturally without cluttering the message."
            ]
        )
    ]

    static var generatedTexts: Set<String> {
        Set(dimensions.flatMap { $0.observations.compactMap { $0 } }.map(normalized))
    }

    static func compile(selections: [String: Int]) -> [String] {
        dimensions.compactMap { $0.observation(for: selections[$0.id] ?? 0) }
    }

    static func replacingQuickSetupObservations(in existing: [String], selections: [String: Int]) -> [String] {
        existing.filter { !generatedTexts.contains(normalized($0)) } + compile(selections: selections)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

nonisolated enum PersonaLimits {
    static let maximumActiveObservations = 20
}
