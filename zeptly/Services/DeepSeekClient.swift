//
//  DeepSeekClient.swift
//  zeptly
//

import Foundation

struct DeepSeekClient: AIProviderClient {
    private let baseURL = URL(string: "https://api.deepseek.com")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        var request = authorizedRequest(path: "/chat/completions", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekChatRequest(
                model: model.rawValue,
                messages: [
                    DeepSeekChatMessage(role: "user", content: "Reply exactly: OK.")
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

        guard
            let choice = completion.choices.first,
            choice.finishReason == "stop",
            choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw ProviderConnectionError.invalidResponse("DeepSeek did not return a completed text response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        var lastError: ProviderConnectionError?

        for attempt in 0..<2 {
            var request = authorizedRequest(path: "/chat/completions", apiKey: apiKey)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                DeepSeekAnalysisRequest(
                    model: model.rawValue,
                    messages: [
                        DeepSeekChatMessage(role: "system", content: ChatScreenshotPrompt.instructions),
                        DeepSeekChatMessage(
                            role: "user",
                            content: ChatScreenshotPrompt.input(for: analysisRequest, retry: attempt > 0)
                        )
                    ],
                    maxTokens: 4_000,
                    temperature: 0,
                    stream: false,
                    thinking: DeepSeekThinking(type: "disabled"),
                    responseFormat: DeepSeekResponseFormat(type: "json_object")
                )
            )

            let (data, response) = try await perform(request)
            try validateHTTPResponse(response, data: data)

            guard let completion = try? JSONDecoder().decode(DeepSeekChatResponse.self, from: data),
                let content = completion.choices.first?.message.content,
                let outputData = content.data(using: .utf8),
                let analysis = try? JSONDecoder().decode(ChatImportAnalysis.self, from: outputData)
            else {
                lastError = .invalidResponse("DeepSeek returned invalid chat data.")
                continue
            }

            do {
                return try analysis.validated(candidateIDs: Set(analysisRequest.candidates.map(\.id)))
            } catch let error as ProviderConnectionError {
                lastError = error
            }
        }

        throw lastError ?? ProviderConnectionError.invalidResponse("DeepSeek returned invalid chat data.")
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
        case 500..<600:
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

private struct DeepSeekAnalysisRequest: Encodable {
    let model: String
    let messages: [DeepSeekChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool
    let thinking: DeepSeekThinking
    let responseFormat: DeepSeekResponseFormat

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
        case thinking
        case responseFormat = "response_format"
    }
}

private struct DeepSeekResponseFormat: Encodable {
    let type: String
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
    let message: DeepSeekResponseMessage
    let finishReason: String

    private enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

private struct DeepSeekResponseMessage: Decodable {
    let content: String
}

private struct DeepSeekErrorResponse: Decodable {
    let error: DeepSeekError
}

private struct DeepSeekError: Decodable {
    let message: String
}
