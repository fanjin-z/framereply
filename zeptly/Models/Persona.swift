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

nonisolated enum PersonaStyleBand: String, Codable, CaseIterable, Sendable {
    case muchLower
    case lower
    case middle
    case higher
    case muchHigher

    var level: Double {
        switch self {
        case .muchLower: -1
        case .lower: -0.5
        case .middle: 0
        case .higher: 0.5
        case .muchHigher: 1
        }
    }

    static func from(level: Double) -> Self {
        let value = min(1, max(-1, level))
        if value <= -0.75 { return .muchLower }
        if value < -0.25 { return .lower }
        if value <= 0.25 { return .middle }
        if value < 0.75 { return .higher }
        return .muchHigher
    }
}

nonisolated struct PersonaStyleDimensionDefinition: Identifiable, Equatable, Sendable {
    let key: String
    let title: String
    let lowAnchor: String
    let highAnchor: String
    let bandLabels: [String]
    let bandInstructions: [String]
    let adjustmentLabels: [String]
    let learnable: Bool
    let userAdjustable: Bool
    let observationOnly: Bool
    let active: Bool
    let order: Int

    var id: String { key }

    func label(for band: PersonaStyleBand) -> String { bandLabels[bandIndex(band)] }
    func instruction(for band: PersonaStyleBand) -> String { bandInstructions[bandIndex(band)] }
    func adjustmentLabel(_ adjustment: Int) -> String {
        adjustmentLabels[min(4, max(0, adjustment + 2))]
    }

    private func bandIndex(_ band: PersonaStyleBand) -> Int {
        switch band {
        case .muchLower: 0
        case .lower: 1
        case .middle: 2
        case .higher: 3
        case .muchHigher: 4
        }
    }
}

nonisolated enum PersonaStyleDimensionRegistry {
    static let version = 1

    static let definitions: [PersonaStyleDimensionDefinition] = [
        .init(
            key: "formality", title: "Formality", lowAnchor: "Casual", highAnchor: "Formal",
            bandLabels: ["Very casual", "Casual", "Balanced", "Formal", "Very formal"],
            bandInstructions: [
                "Use relaxed, conversational wording and natural contractions.",
                "Keep the wording casual and conversational.",
                "Use polished but conversational wording.",
                "Use polished, complete phrasing while remaining conversational.",
                "Use highly polished, formal phrasing and avoid slang."
            ],
            adjustmentLabels: ["Much more casual", "More casual", "Current", "More formal", "Much more formal"],
            learnable: true, userAdjustable: true, observationOnly: false, active: true, order: 0
        ),
        .init(
            key: "warmth", title: "Warmth", lowAnchor: "Cooler", highAnchor: "Warmer",
            bandLabels: ["Very reserved", "Reserved", "Balanced", "Warm", "Very warm"],
            bandInstructions: [
                "Be restrained and emotionally neutral.",
                "Show limited warmth while staying courteous.",
                "Use a balanced, friendly emotional tone.",
                "Show clear warmth and considerate acknowledgment.",
                "Be openly warm and empathetic without inventing feelings."
            ],
            adjustmentLabels: ["Much cooler", "Cooler", "Current", "Warmer", "Much warmer"],
            learnable: true, userAdjustable: true, observationOnly: false, active: true, order: 1
        ),
        .init(
            key: "length", title: "Reply Length", lowAnchor: "Shorter", highAnchor: "Longer",
            bandLabels: ["Very short", "Short", "Balanced", "Detailed", "Very detailed"],
            bandInstructions: [
                "Reply in one very concise sentence when possible.",
                "Keep the reply concise and omit nonessential detail.",
                "Use the amount of detail naturally required by the message.",
                "Give a somewhat fuller reply with useful context.",
                "Use a detailed reply while avoiding repetition and filler."
            ],
            adjustmentLabels: ["Much shorter", "Shorter", "Current", "Longer", "Much longer"],
            learnable: true, userAdjustable: true, observationOnly: false, active: true, order: 2
        ),
        .init(
            key: "emoji", title: "Emoji", lowAnchor: "Fewer", highAnchor: "More",
            bandLabels: ["No emoji", "Few emoji", "Occasional emoji", "Frequent emoji", "Expressive emoji"],
            bandInstructions: [
                "Do not use emoji unless required by an Always Follow rule.",
                "Use emoji rarely and only when it reads naturally.",
                "Use an occasional emoji only when it fits the conversation.",
                "Use emoji fairly often while keeping the message readable.",
                "Use expressive emoji naturally without cluttering the reply."
            ],
            adjustmentLabels: ["Much fewer", "Fewer", "Current", "More", "Much more"],
            learnable: true, userAdjustable: true, observationOnly: false, active: true, order: 3
        ),
        .init(
            key: "directness", title: "Directness", lowAnchor: "Indirect", highAnchor: "Direct",
            bandLabels: ["Very indirect", "Tactful", "Balanced", "Direct", "Very direct"],
            bandInstructions: [
                "Approach requests and disagreement very indirectly.", "Favor tactful, softened phrasing.",
                "Balance clarity with tact.", "State the main point clearly and directly.",
                "Lead with the point and avoid hedging."
            ],
            adjustmentLabels: ["Much less direct", "Less direct", "Current", "More direct", "Much more direct"],
            learnable: true, userAdjustable: false, observationOnly: false, active: true, order: 4
        ),
        .init(
            key: "humor", title: "Humor", lowAnchor: "Serious", highAnchor: "Playful",
            bandLabels: ["Very serious", "Mostly serious", "Balanced", "Playful", "Very playful"],
            bandInstructions: [
                "Keep the tone serious.", "Use humor rarely.", "Use humor only when context naturally invites it.",
                "Allow light playfulness when appropriate.", "Use a strongly playful voice without forcing jokes."
            ],
            adjustmentLabels: ["Much less playful", "Less playful", "Current", "More playful", "Much more playful"],
            learnable: true, userAdjustable: false, observationOnly: false, active: true, order: 5
        ),
        observation(key: "grammarAndCasing", title: "Grammar & Casing", order: 6),
        observation(key: "punctuation", title: "Punctuation", order: 7),
        observation(key: "vocabulary", title: "Word Choice", order: 8),
        observation(key: "languageMixing", title: "Language Mixing", order: 9)
    ]

    static var activeDefinitions: [PersonaStyleDimensionDefinition] {
        definitions.filter(\.active).sorted { $0.order < $1.order }
    }

    static var learnableDefinitions: [PersonaStyleDimensionDefinition] {
        activeDefinitions.filter(\.learnable)
    }

    static var adjustableDefinitions: [PersonaStyleDimensionDefinition] {
        activeDefinitions.filter(\.userAdjustable)
    }

    static func definition(for key: String) -> PersonaStyleDimensionDefinition? {
        activeDefinitions.first { $0.key == key }
    }

    static func presetBaseline(for template: PersonaTemplate) -> [String: Double] {
        switch template {
        case .professional:
            ["formality": 0.6, "warmth": 0, "length": -0.5, "emoji": -1, "directness": 0.5, "humor": -0.5]
        case .spark:
            ["formality": -0.6, "warmth": 0.6, "length": -0.5, "emoji": 0.25, "directness": 0.25, "humor": 0.6]
        case .thoughtful:
            ["formality": 0, "warmth": 0.7, "length": 0, "emoji": 0.1, "directness": -0.2, "humor": 0]
        }
    }

    private static func observation(key: String, title: String, order: Int) -> PersonaStyleDimensionDefinition {
        .init(
            key: key, title: title, lowAnchor: "", highAnchor: "",
            bandLabels: Array(repeating: "", count: 5), bandInstructions: Array(repeating: "", count: 5),
            adjustmentLabels: Array(repeating: "Current", count: 5),
            learnable: true, userAdjustable: false, observationOnly: true, active: true, order: order
        )
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

nonisolated enum PersonaStyleSource: String, Codable, Sendable {
    case preset
    case learnedVoice
    case learnedWithAdjustment
    case userCorrected

    var displayName: String {
        switch self {
        case .preset: "Preset"
        case .learnedVoice: "Learned voice"
        case .learnedWithAdjustment: "Learned voice · adjusted"
        case .userCorrected: "Your correction"
        }
    }
}

nonisolated struct PersonaLearnedTrait: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var dimensionKey: String
    var learnedLevel: Double?
    var observation: String
    var confidence: Double
    var evidenceCount: Int
    var origin: PersonaTraitOrigin
    var status: PersonaTraitStatus
    var updatedAt: Date
}

nonisolated struct PersonaResolvedStyleSignal: Codable, Equatable, Sendable {
    let dimensionKey: String
    let title: String
    let shortLabel: String
    let descriptor: String
    let instruction: String
    let source: PersonaStyleSource
}

nonisolated struct PersonaPromptContext: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let purposeInstructions: String
    let resolvedStyle: [PersonaResolvedStyleSignal]
    let descriptiveObservations: [PersonaLearnedTrait]
    let alwaysFollowRules: String
    let registryVersion: Int
    let resolverVersion: Int
}

struct Persona: Identifiable, Equatable {
    let id: UUID
    var name: String
    var summary: String
    var symbolName: String
    var accentKey: String
    var template: PersonaTemplate
    var isBuiltIn: Bool
    var purposeInstructions: String
    var baselineStyle: [String: Double]
    var alwaysFollowRules: String
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

nonisolated enum PersonaStyleResolver {
    static let version = 1

    static func confidence(evidenceCount: Int, origin: PersonaTraitOrigin) -> Double {
        if origin == .userConfirmed { return 1 }
        return min(0.85, 0.25 + Double(max(1, evidenceCount)) * 0.10)
    }

    static func resolve(
        baseline: [String: Double],
        adjustments: [String: Int],
        traits: [PersonaLearnedTrait]
    ) -> [PersonaResolvedStyleSignal] {
        let activeTraits = Dictionary(uniqueKeysWithValues: traits.filter { $0.status == .active }.map { ($0.dimensionKey, $0) })
        return PersonaStyleDimensionRegistry.activeDefinitions.compactMap { definition in
            guard !definition.observationOnly else { return nil }
            let preset = min(1, max(-1, baseline[definition.key] ?? 0))
            let trait = activeTraits[definition.key]
            let confidence = trait?.learnedLevel == nil ? 0 : min(1, max(0, trait?.confidence ?? 0))
            let learned = trait?.learnedLevel ?? preset
            let voiceLevel = preset * (1 - confidence) + learned * confidence
            let adjustment = definition.userAdjustable ? min(2, max(-2, adjustments[definition.key] ?? 0)) : 0
            let resolved = min(1, max(-1, voiceLevel + Double(adjustment) * 0.20))
            let band = PersonaStyleBand.from(level: resolved)
            let source: PersonaStyleSource
            if trait?.origin == .userConfirmed {
                source = .userCorrected
            } else if adjustment != 0, trait != nil {
                source = .learnedWithAdjustment
            } else if trait != nil {
                source = .learnedVoice
            } else {
                source = .preset
            }
            return PersonaResolvedStyleSignal(
                dimensionKey: definition.key,
                title: definition.title,
                shortLabel: definition.label(for: band),
                descriptor: definition.label(for: band).lowercased(),
                instruction: definition.instruction(for: band),
                source: source
            )
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
