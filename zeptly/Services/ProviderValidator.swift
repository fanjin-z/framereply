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

nonisolated struct ProviderInvalidRequestError: Error, Equatable, Sendable {
    let provider: String
    let httpStatus: Int
    let providerCode: String?
    let message: String
}

nonisolated enum ProviderConnectionError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidKey
    case insufficientBalance
    case rateLimited
    case providerUnavailable
    case invalidRequest(ProviderInvalidRequestError)
    case invalidResponse(String)
    case structuredOutput(ProviderStructuredOutputError)
    case networkFailure(String)
    case keychainFailure(String)
    case dataConsentRequired
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
        case .invalidRequest(let error):
            error.message
        case .invalidResponse(let message):
            message
        case .structuredOutput(let error):
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
        case .networkFailure(let message):
            message
        case .keychainFailure(let message):
            "The API key was valid, but Zeptly could not save it securely. \(message)"
        case .dataConsentRequired:
            "Allow provider data sharing before connecting."
        case .unsupportedProvider:
            "This provider is not available yet."
        }
    }

    var shortcutErrorCode: String {
        switch self {
        case .invalidRequest:
            "provider_invalid_request"
        case .structuredOutput(let error):
            error.failure.kind.shortcutErrorCode
        default:
            "provider_error"
        }
    }
}
