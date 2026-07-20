//
//  ProviderValidator.swift
//  FrameReply
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
            String(localized: AppStrings.Errors.Provider.missingKey)
        case .invalidKey:
            String(localized: AppStrings.Errors.Provider.invalidKey)
        case .insufficientBalance:
            String(localized: AppStrings.Errors.Provider.insufficientBalance)
        case .rateLimited:
            String(localized: AppStrings.Errors.Provider.rateLimited)
        case .providerUnavailable:
            String(localized: AppStrings.Errors.Provider.unavailable)
        case .invalidRequest:
            String(localized: AppStrings.Errors.Provider.invalidRequest)
        case .invalidResponse:
            String(localized: AppStrings.Errors.Provider.invalidResponse)
        case .structuredOutput(let error):
            switch error.failure.kind {
            case .emptyResponse:
                String(localized: AppStrings.Errors.Provider.emptyResponse)
            case .truncatedResponse:
                String(localized: AppStrings.Errors.Provider.truncatedResponse)
            case .invalidJSON:
                String(localized: AppStrings.Errors.Provider.invalidJSON)
            case .schemaMismatch:
                String(localized: AppStrings.Errors.Provider.schemaMismatch)
            case .invalidCandidateID:
                String(localized: AppStrings.Errors.Provider.invalidChat)
            case .incompleteMessages:
                String(localized: AppStrings.Errors.Provider.incompleteMessages)
            }
        case .networkFailure:
            String(localized: AppStrings.Errors.Provider.network)
        case .keychainFailure:
            String(localized: AppStrings.Errors.Provider.keychain)
        case .dataConsentRequired:
            String(localized: AppStrings.Errors.Provider.consentRequired)
        case .unsupportedProvider:
            String(localized: AppStrings.Errors.Provider.unsupported)
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
