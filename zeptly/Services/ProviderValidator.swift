//
//  ProviderValidator.swift
//  zeptly
//

import Foundation

protocol ProviderValidator {
    func validate(apiKey: String, model: ProviderModel) async throws
}

protocol ChatScreenshotAnalyzing {
    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis
}

protocol AIProviderClient: ProviderValidator, ChatScreenshotAnalyzing {}

nonisolated enum ProviderConnectionError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidKey
    case insufficientBalance
    case rateLimited
    case providerUnavailable
    case invalidResponse(String)
    case structuredOutput(ProviderStructuredOutputError)
    case networkFailure(String)
    case keychainFailure(String)
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Enter an API key before saving."
        case .invalidKey:
            "This provider rejected the API key. Check it and try again."
        case .insufficientBalance:
            "This account does not have enough available API credit or quota."
        case .rateLimited:
            "This provider is rate limiting the key. Wait a moment and try again."
        case .providerUnavailable:
            "This provider is temporarily unavailable. Try again shortly."
        case let .invalidResponse(message):
            message
        case let .structuredOutput(error):
            switch error.failure.kind {
            case .emptyResponse:
                "The provider returned an empty response."
            case .truncatedResponse:
                "The provider response was cut off before it finished."
            case .invalidJSON:
                "The provider returned malformed JSON."
            case .schemaMismatch:
                "The provider response did not match the chat format."
            case .invalidCandidateID:
                "The provider selected an unknown chat."
            case .incompleteMessages:
                "The provider returned incomplete chat messages."
            }
        case let .networkFailure(message):
            message
        case let .keychainFailure(message):
            "The API key was valid, but Zeptly could not save it securely. \(message)"
        case .unsupportedProvider:
            "This provider is not available yet."
        }
    }

    var shortcutErrorCode: String {
        switch self {
        case let .structuredOutput(error):
            error.failure.kind.shortcutErrorCode
        default:
            "provider_error"
        }
    }
}
