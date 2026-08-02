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
    case zaiInternational
    case zhipuChina

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
        case .zaiInternational:
            "Z.ai International"
        case .zhipuChina:
            "智谱 (国内)"
        }
    }

    var symbolName: String {
        switch self {
        case .openAI:
            "waveform"
        case .openRouter:
            "network"
        case .miniMaxInternational, .miniMaxChina, .zaiInternational, .zhipuChina:
            "sparkles.rectangle.stack"
        }
    }

    var supportedTiers: [ProviderTier] {
        switch self {
        case .openRouter, .miniMaxInternational, .miniMaxChina:
            [.advanced]
        case .openAI, .zaiInternational, .zhipuChina:
            ProviderTier.allCases
        }
    }
    var defaultTier: ProviderTier { .advanced }

    func models(for tier: ProviderTier) -> (analysis: ProviderModel, replies: ProviderModel) {
        switch (self, tier) {
        case (.openAI, .basic):
            (.gpt56Luna, .gpt56Luna)
        case (.openAI, .advanced):
            (.gpt56Terra, .gpt56Terra)
        case (.openAI, .best):
            (.gpt56Sol, .gpt56Sol)
        case (.openRouter, _):
            (.qwen37Plus, .qwen37Plus)
        case (.miniMaxInternational, _), (.miniMaxChina, _):
            (.miniMaxM3, .miniMaxM3)
        case (.zaiInternational, .basic):
            (.glm46VFlash, .glm47Flash)
        case (.zaiInternational, .advanced):
            (.glm46VFlashX, .glm47FlashX)
        case (.zaiInternational, .best):
            (.glm46V, .glm47)
        case (.zhipuChina, .basic):
            (.glm46VFlash, .glm47Flash)
        case (.zhipuChina, .advanced):
            (.glm46VFlashX, .glm47FlashX)
        case (.zhipuChina, .best):
            (.glm46V, .glm47)
        }
    }

    func modelSummary(for tier: ProviderTier) -> String {
        models(for: tier).analysis.displayName
    }
}

enum ProviderModel: String, Codable {
    case gpt56Luna = "gpt-5.6-luna"
    case gpt56Terra = "gpt-5.6-terra"
    case gpt56Sol = "gpt-5.6-sol"
    case glm46VFlashX = "glm-4.6v-flashx"
    case glm46VFlash = "glm-4.6v-flash"
    case glm46V = "glm-4.6v"
    case glm47FlashX = "glm-4.7-flashx"
    case glm47Flash = "glm-4.7-flash"
    case glm47 = "glm-4.7"
    case qwen37Plus = "qwen/qwen3.7-plus"
    case miniMaxM3 = "MiniMax-M3"

    nonisolated var displayName: String {
        switch self {
        case .gpt56Luna:
            "GPT-5.6 Luna"
        case .gpt56Terra:
            "GPT-5.6 Terra"
        case .gpt56Sol:
            "GPT-5.6 Sol"
        case .glm46VFlashX:
            "GLM-4.6V FlashX"
        case .glm46VFlash:
            "GLM-4.6V Flash"
        case .glm46V:
            "GLM-4.6V"
        case .glm47FlashX:
            "GLM-4.7 FlashX"
        case .glm47Flash:
            "GLM-4.7 Flash"
        case .glm47:
            "GLM-4.7"
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
            "Recommended for consistently strong results at moderate cost"
        case .best:
            "Highest-quality interpretation and writing at the highest cost"
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
