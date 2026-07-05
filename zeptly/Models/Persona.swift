import Foundation
import SwiftUI

nonisolated enum PersonaTemplate: String, Codable, CaseIterable, Sendable {
    case professional
    case spark
    case thoughtful

    var displayName: String {
        switch self {
        case .professional: "The Professional"
        case .spark: "The Spark"
        case .thoughtful: "The Thoughtful"
        }
    }
}

nonisolated enum PersonaFormality: String, Codable, CaseIterable, Sendable {
    case casual, balanced, formal
}

nonisolated enum PersonaWarmth: String, Codable, CaseIterable, Sendable {
    case reserved, balanced, warm
}

nonisolated enum PersonaLength: String, Codable, CaseIterable, Sendable {
    case short, balanced, detailed
}

nonisolated enum PersonaEmojiUse: String, Codable, CaseIterable, Sendable {
    case none, light, expressive
}

nonisolated enum PersonaTraitCategory: String, Codable, CaseIterable, Sendable {
    case length
    case formality
    case warmth
    case directness
    case grammarAndCasing
    case punctuation
    case emoji
    case vocabulary
    case humor
    case languageMixing

    var displayName: String {
        switch self {
        case .length: "Message length"
        case .formality: "Formality"
        case .warmth: "Warmth"
        case .directness: "Directness"
        case .grammarAndCasing: "Grammar & casing"
        case .punctuation: "Punctuation"
        case .emoji: "Emoji"
        case .vocabulary: "Word choice"
        case .humor: "Humor"
        case .languageMixing: "Language mixing"
        }
    }
}

nonisolated enum PersonaTraitOrigin: String, Codable, Sendable {
    case aiInferred
    case userConfirmed
}

nonisolated enum PersonaTraitStatus: String, Codable, Sendable {
    case active
    case dismissed
}

nonisolated struct PersonaLearnedTrait: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var category: PersonaTraitCategory
    var observation: String
    var confidence: Double
    var evidenceCount: Int
    var origin: PersonaTraitOrigin
    var status: PersonaTraitStatus
    var updatedAt: Date
}

nonisolated struct PersonaPromptContext: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let baseInstructions: String
    let formality: PersonaFormality
    let warmth: PersonaWarmth
    let length: PersonaLength
    let emojiUse: PersonaEmojiUse
    let additionalGuidance: String
    let learnedTraits: [PersonaLearnedTrait]
}

struct Persona: Identifiable, Equatable {
    let id: UUID
    var name: String
    var summary: String
    var symbolName: String
    var accentKey: String
    var template: PersonaTemplate
    var isBuiltIn: Bool
    var baseInstructions: String
    var formality: PersonaFormality
    var warmth: PersonaWarmth
    var length: PersonaLength
    var emojiUse: PersonaEmojiUse
    var additionalGuidance: String
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

nonisolated enum PersonaDefaults {
    static let professionalID = UUID(uuidString: "A0111111-1111-4111-8111-111111111111")!
    static let sparkID = UUID(uuidString: "A0222222-2222-4222-8222-222222222222")!
    static let thoughtfulID = UUID(uuidString: "A0333333-3333-4333-8333-333333333333")!

    static func id(for template: PersonaTemplate) -> UUID {
        switch template {
        case .professional: professionalID
        case .spark: sparkID
        case .thoughtful: thoughtfulID
        }
    }
}
