//
//  ProviderValidator.swift
//  zeptly
//

import Foundation

protocol ProviderValidator {
    func validate(apiKey: String, model: ProviderModel) async throws
}

enum ProviderConnectionError: LocalizedError {
    case missingAPIKey
    case invalidKey
    case insufficientBalance
    case rateLimited
    case providerUnavailable
    case invalidResponse(String)
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
        case let .networkFailure(message):
            message
        case let .keychainFailure(message):
            "The API key was valid, but Zeptly could not save it securely. \(message)"
        case .unsupportedProvider:
            "This provider is not available yet."
        }
    }
}
