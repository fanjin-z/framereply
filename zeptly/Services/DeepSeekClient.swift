//
//  DeepSeekClient.swift
//  zeptly
//

import Foundation

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

struct DeepSeekClient {
    private let baseURL = URL(string: "https://api.deepseek.com")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        try await validateBalance(apiKey: apiKey)
        try await ping(apiKey: apiKey, model: model)
    }

    private func validateBalance(apiKey: String) async throws {
        let request = authorizedRequest(path: "/user/balance", apiKey: apiKey)
        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)

        let balance: DeepSeekBalanceResponse
        do {
            balance = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse("DeepSeek balance check returned an unexpected response.")
        }

        guard balance.isAvailable else {
            throw ProviderConnectionError.insufficientBalance
        }
    }

    private func ping(apiKey: String, model: ProviderModel) async throws {
        var request = authorizedRequest(path: "/chat/completions", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekChatRequest(
                model: model.rawValue,
                messages: [
                    DeepSeekChatMessage(role: "user", content: "Say OK.")
                ],
                maxTokens: 2,
                temperature: 0,
                stream: false,
                thinking: DeepSeekThinking(type: "disabled")
            )
        )

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)

        let completion: DeepSeekChatResponse
        do {
            completion = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse("DeepSeek completion check returned an unexpected response.")
        }

        guard completion.choices.isEmpty == false else {
            throw ProviderConnectionError.invalidResponse("DeepSeek completion check returned no choices.")
        }
    }

    private func authorizedRequest(path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure("Could not reach DeepSeek. Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse("DeepSeek returned an invalid HTTP response.")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw ProviderConnectionError.invalidKey
        case 402:
            throw ProviderConnectionError.insufficientBalance
        case 429:
            throw ProviderConnectionError.rateLimited
        case 500, 503:
            throw ProviderConnectionError.providerUnavailable
        default:
            throw ProviderConnectionError.invalidResponse(
                deepSeekErrorMessage(from: data)
                    ?? "DeepSeek returned HTTP \(httpResponse.statusCode)."
            )
        }
    }

    private func deepSeekErrorMessage(from data: Data) -> String? {
        guard
            let response = try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data),
            response.error.message.isEmpty == false
        else {
            return nil
        }

        return response.error.message
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
    }
}

private struct DeepSeekChatRequest: Encodable {
    let model: String
    let messages: [DeepSeekChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool
    let thinking: DeepSeekThinking

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
        case thinking
    }
}

private struct DeepSeekChatMessage: Encodable {
    let role: String
    let content: String
}

private struct DeepSeekThinking: Encodable {
    let type: String
}

private struct DeepSeekChatResponse: Decodable {
    let choices: [DeepSeekChoice]
}

private struct DeepSeekChoice: Decodable {
    let index: Int
}

private struct DeepSeekErrorResponse: Decodable {
    let error: DeepSeekError
}

private struct DeepSeekError: Decodable {
    let message: String
}
