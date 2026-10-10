//
//  ProviderConnection.swift
//  FrameReply
//

import Foundation

nonisolated enum ProviderPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case openAI
    case openRouter
    case miniMaxInternational
    case miniMaxChina
    case frameReplyAI

    static var availableCases: [ProviderPlatform] { allCases.filter { $0 != .frameReplyAI } }

    var id: String { rawValue }

    var keychainAccount: String { "provider.\(rawValue).apiKey" }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openRouter:
            "OpenRouter"
        case .miniMaxInternational:
            String(localized: AppStrings.Provider.miniMaxInternationalName)
        case .miniMaxChina:
            String(localized: AppStrings.Provider.miniMaxChinaName)
        case .frameReplyAI:
            String(localized: "FrameReply AI Access")
        }
    }

    var symbolName: String {
        switch self {
        case .openAI:
            "waveform"
        case .openRouter:
            "network"
        case .miniMaxInternational, .miniMaxChina:
            "sparkles.rectangle.stack"
        case .frameReplyAI:
            "sparkles"
        }
    }

    var supportedTiers: [ProviderTier] {
        switch self {
        case .openRouter, .miniMaxInternational, .miniMaxChina:
            [.advanced]
        case .openAI:
            ProviderTier.allCases
        case .frameReplyAI:
            [.basic]
        }
    }
    var defaultTier: ProviderTier {
        switch self {
        case .openAI:
            .basic
        case .frameReplyAI:
            .basic
        case .openRouter, .miniMaxInternational, .miniMaxChina:
            .advanced
        }
    }

    func models(for tier: ProviderTier) -> (analysis: ProviderModel, replies: ProviderModel)? {
        switch (self, tier) {
        case (.openAI, .basic):
            (.gpt6Luna, .gpt6Luna)
        case (.openAI, .advanced):
            (.gpt56Terra, .gpt56Terra)
        case (.openAI, .best):
            (.gpt61Sol, .gpt61Sol)
        case (.openRouter, _):
            (.qwen37Plus, .qwen37Plus)
        case (.frameReplyAI, _):
            nil
        case (.miniMaxInternational, _), (.miniMaxChina, _):
            (.miniMaxM3, .miniMaxM3)
        }
    }

    func modelSummary(for tier: ProviderTier) -> String {
        models(for: tier)?.analysis.displayName ?? String(localized: "Managed AI")
    }
}

nonisolated struct ManagedOpenRouterModelID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard
            rawValue.range(
                of: #"\A[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._:-]{0,127}\z"#,
                options: .regularExpression
            ) != nil
        else { return nil }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let model = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid managed OpenRouter model ID"
            )
        }
        self = model
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct ManagedOpenRouterModel: Hashable, Codable, Sendable {
    let requestID: ManagedOpenRouterModelID
    let responseID: ManagedOpenRouterModelID
}

nonisolated enum ProviderModel: Hashable, Codable, Sendable {
    case gpt6Luna
    case gpt56Terra
    case gpt61Sol
    case qwen37Plus
    case miniMaxM3
    case managedOpenRouter(ManagedOpenRouterModel)

    var rawValue: String {
        switch self {
        case .gpt6Luna: "gpt-6-luna"
        case .gpt56Terra: "gpt-5.6-terra"
        case .gpt61Sol: "gpt-6.1-sol"
        case .qwen37Plus: "qwen/qwen3.7-plus"
        case .miniMaxM3: "MiniMax-M3"
        case .managedOpenRouter(let model): model.requestID.rawValue
        }
    }

    func acceptsResponseID(_ responseID: String) -> Bool {
        if case .managedOpenRouter(let model) = self {
            return responseID == model.requestID.rawValue
                || responseID == model.responseID.rawValue
        }
        return responseID == rawValue
    }

    var isManagedOpenRouterModel: Bool {
        if case .managedOpenRouter = self { return true }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let model = try? container.decode(ManagedOpenRouterModel.self) {
            self = .managedOpenRouter(model)
            return
        }
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "gpt-6-luna": self = .gpt6Luna
        case "gpt-5.6-terra": self = .gpt56Terra
        case "gpt-6.1-sol": self = .gpt61Sol
        case "qwen/qwen3.7-plus": self = .qwen37Plus
        case "MiniMax-M3": self = .miniMaxM3
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid provider model ID"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if case .managedOpenRouter(let model) = self {
            try container.encode(model)
        } else {
            try container.encode(rawValue)
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .gpt6Luna:
            "GPT-6 Luna"
        case .gpt56Terra:
            "GPT-5.6 Terra"
        case .gpt61Sol:
            "GPT-6.1 Sol"
        case .qwen37Plus:
            "Qwen3.7 Plus"
        case .miniMaxM3:
            "MiniMax M3"
        case .managedOpenRouter:
            String(localized: "Managed AI")
        }
    }
}

enum ProviderTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic
    case advanced
    case best

    var id: String { rawValue }

    var localizedDisplayName: LocalizedStringResource {
        switch self {
        case .basic: "Basic"
        case .advanced: "Advanced"
        case .best: "Best"
        }
    }

    var displayName: String {
        String(localized: localizedDisplayName)
    }

    var localizedDetail: LocalizedStringResource {
        switch self {
        case .basic:
            "Lowest cost; may be less reliable with subtle or complex context"
        case .advanced:
            "Consistently strong results for complex context"
        case .best:
            "Highest-quality interpretation and writing"
        }
    }

    var detail: String {
        String(localized: localizedDetail)
    }
}

struct ProviderConnection: Identifiable, Codable {
    var id: UUID = UUID()
    let platform: ProviderPlatform
    var tier: ProviderTier
    var managedModel: ManagedOpenRouterModel?
    var managedExpiresAt: Date?
    var managedConsent: ManagedAIConsent?

    init(
        id: UUID = UUID(), platform: ProviderPlatform, tier: ProviderTier,
        managedModel: ManagedOpenRouterModel? = nil, managedExpiresAt: Date? = nil,
        managedConsent: ManagedAIConsent? = nil
    ) {
        self.id = id
        self.platform = platform
        self.tier = tier
        self.managedModel = managedModel
        self.managedExpiresAt = managedExpiresAt
        self.managedConsent = managedConsent
    }

    var name: String { platform.displayName }
    var symbolName: String { platform.symbolName }
}
