//
//  ProviderConnection.swift
//  FrameReply
//

import Foundation

nonisolated enum ProviderPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case openAI
    case zaiInternational
    case zhipuChina

    static var availableCases: [ProviderPlatform] { allCases }

    var id: String { rawValue }

    var keychainAccount: String { "provider.\(rawValue).apiKey" }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
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
        case .zaiInternational:
            "sparkles.rectangle.stack"
        case .zhipuChina:
            "sparkles.rectangle.stack"
        }
    }

    var supportedTiers: [ProviderTier] { ProviderTier.allCases }
    var defaultTier: ProviderTier { .advanced }

    func models(for tier: ProviderTier) -> (analysis: ProviderModel, replies: ProviderModel) {
        switch (self, tier) {
        case (.openAI, .basic):
            (.gpt56Luna, .gpt56Luna)
        case (.openAI, .advanced):
            (.gpt56Terra, .gpt56Terra)
        case (.openAI, .best):
            (.gpt56Sol, .gpt56Sol)
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
        models(for: tier).analysis.rawValue
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
