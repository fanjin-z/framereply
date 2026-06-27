//
//  ProviderConnection.swift
//  zeptly
//

import Foundation
import SwiftUI

enum ProviderPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case deepSeek
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeek:
            "DeepSeek"
        case .openAI:
            "OpenAI"
        }
    }

    var symbolName: String {
        switch self {
        case .deepSeek:
            "sparkles"
        case .openAI:
            "waveform"
        }
    }

    var isConnectable: Bool {
        switch self {
        case .deepSeek:
            true
        case .openAI:
            true
        }
    }

    var supportedModels: [ProviderModel] {
        switch self {
        case .deepSeek:
            [.deepSeekV4Flash, .deepSeekV4Pro]
        case .openAI:
            [.gpt54Mini, .gpt54, .gpt55]
        }
    }
}

enum ProviderModel: String, Codable, CaseIterable, Identifiable {
    case deepSeekV4Flash = "deepseek-v4-flash"
    case deepSeekV4Pro = "deepseek-v4-pro"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeekV4Flash:
            "Flash"
        case .deepSeekV4Pro:
            "Pro"
        case .gpt54Mini:
            "Balanced"
        case .gpt54:
            "Advanced"
        case .gpt55:
            "Best"
        }
    }

    var detail: String {
        switch self {
        case .deepSeekV4Flash:
            "Lower cost and faster replies"
        case .deepSeekV4Pro:
            "Stronger reasoning for complex work"
        case .gpt54Mini:
            "High-quality replies at a balanced cost"
        case .gpt54:
            "Stronger reasoning and tone handling"
        case .gpt55:
            "Highest-quality, polished replies"
        }
    }

    var platform: ProviderPlatform {
        switch self {
        case .deepSeekV4Flash, .deepSeekV4Pro:
            .deepSeek
        case .gpt54Mini, .gpt54, .gpt55:
            .openAI
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
    var isEnabled: Bool
    var validationState: ProviderValidationState

    var name: String { platform.displayName }
    var symbolName: String { platform.symbolName }
    var modelName: String { model.rawValue }

    var displayValidationState: ProviderValidationState {
        isEnabled ? validationState : .paused
    }

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
