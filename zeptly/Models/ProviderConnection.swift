//
//  ProviderConnection.swift
//  zeptly
//

import Foundation
import SwiftUI

enum ProviderPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case openAI
    case zaiInternational
    case zhipuChina

    var id: String { rawValue }

    var keychainAccount: String { "provider.\(rawValue).apiKey" }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .zaiInternational:
            "Z.ai International"
        case .zhipuChina:
            "智谱AI(中国)"
        }
    }

    var symbolName: String {
        switch self {
        case .openAI:
            "waveform"
        case .zaiInternational, .zhipuChina:
            "sparkles.rectangle.stack"
        }
    }

    var isConnectable: Bool {
        true
    }

    var supportedModels: [ProviderModel] {
        switch self {
        case .openAI:
            [.gpt54Mini, .gpt54, .gpt55]
        case .zaiInternational, .zhipuChina:
            [.glm46VFlashX, .glm46VFlash, .glm46V]
        }
    }
}

enum ProviderModel: String, Codable, CaseIterable, Identifiable {
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"
    case glm46VFlashX = "glm-4.6v-flashx"
    case glm46VFlash = "glm-4.6v-flash"
    case glm46V = "glm-4.6v"
    case glm47FlashX = "glm-4.7-flashx"
    case glm47Flash = "glm-4.7-flash"
    case glm47 = "glm-4.7"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt54Mini:
            "Balanced"
        case .gpt54:
            "Advanced"
        case .gpt55:
            "Best"
        case .glm46VFlashX:
            "Default"
        case .glm46VFlash:
            "Free"
        case .glm46V:
            "Quality"
        case .glm47FlashX:
            "Default Replies"
        case .glm47Flash:
            "Free Replies"
        case .glm47:
            "Quality Replies"
        }
    }

    var detail: String {
        switch self {
        case .gpt54Mini:
            "High-quality replies at a balanced cost"
        case .gpt54:
            "Stronger reasoning and tone handling"
        case .gpt55:
            "Highest-quality, polished replies"
        case .glm46VFlashX:
            "Fast screenshot analysis and everyday replies"
        case .glm46VFlash:
            "Free screenshot analysis and replies"
        case .glm46V:
            "Highest-quality GLM analysis and replies"
        case .glm47FlashX:
            "Fast text generation for everyday replies"
        case .glm47Flash:
            "Free text generation for replies"
        case .glm47:
            "Highest-quality GLM text generation"
        }
    }

}

enum ProviderValidationState: String, Codable {
    case connected
    case paused
    case invalidKey
    case insufficientBalance
    case rateLimited
    case providerError
    case notValidated

    var title: String {
        switch self {
        case .connected:
            "Connected"
        case .paused:
            "Paused"
        case .invalidKey:
            "Invalid key"
        case .insufficientBalance:
            "Insufficient balance"
        case .rateLimited:
            "Rate limited"
        case .providerError:
            "Provider error"
        case .notValidated:
            "Not validated"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            RezplyColor.connected
        case .paused, .notValidated:
            RezplyColor.outlineVariant
        case .invalidKey, .insufficientBalance, .rateLimited, .providerError:
            RezplyColor.peach
        }
    }
}

struct ProviderConnection: Identifiable, Codable {
    var id: UUID = UUID()
    let platform: ProviderPlatform
    var model: ProviderModel
    var lastValidatedAt: Date?
    var validationState: ProviderValidationState

    var name: String { platform.displayName }
    var symbolName: String { platform.symbolName }
    var modelName: String { model.rawValue }

    var lastSynced: String {
        guard let lastValidatedAt else {
            return "Never"
        }

        if abs(lastValidatedAt.timeIntervalSinceNow) < 60 {
            return "Just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastValidatedAt, relativeTo: Date())
    }
}
