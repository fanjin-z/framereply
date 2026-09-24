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

    static var availableCases: [ProviderPlatform] { allCases }

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
        }
    }

    var supportedTiers: [ProviderTier] {
        switch self {
        case .openRouter, .miniMaxInternational, .miniMaxChina:
            [.advanced]
        case .openAI:
            ProviderTier.allCases
        }
    }
    var defaultTier: ProviderTier {
        switch self {
        case .openAI:
            .basic
        case .openRouter, .miniMaxInternational, .miniMaxChina:
            .advanced
        }
    }

    func models(for tier: ProviderTier) -> (analysis: ProviderModel, replies: ProviderModel) {
        switch (self, tier) {
        case (.openAI, .basic):
            (.gpt6Luna, .gpt6Luna)
        case (.openAI, .advanced):
            (.gpt56Terra, .gpt56Terra)
        case (.openAI, .best):
            (.gpt6Sol, .gpt6Sol)
        case (.openRouter, _):
            (.qwen37Plus, .qwen37Plus)
        case (.miniMaxInternational, _), (.miniMaxChina, _):
            (.miniMaxM3, .miniMaxM3)
        }
    }

    func modelSummary(for tier: ProviderTier) -> String {
        models(for: tier).analysis.displayName
    }
}

enum ProviderModel: String, Codable {
    case gpt6Luna = "gpt-6-luna"
    case gpt56Terra = "gpt-5.6-terra"
    case gpt6Sol = "gpt-6-sol"
    case qwen37Plus = "qwen/qwen3.7-plus"
    case miniMaxM3 = "MiniMax-M3"

    nonisolated var displayName: String {
        switch self {
        case .gpt6Luna:
            "GPT-6 Luna"
        case .gpt56Terra:
            "GPT-5.6 Terra"
        case .gpt6Sol:
            "GPT-6 Sol"
        case .qwen37Plus:
            "Qwen3.7 Plus"
        case .miniMaxM3:
            "MiniMax M3"
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

    var name: String { platform.displayName }
    var symbolName: String { platform.symbolName }
}
