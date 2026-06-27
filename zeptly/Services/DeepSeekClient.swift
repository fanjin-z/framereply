//
//  DeepSeekClient.swift
//  zeptly
//

import Foundation

struct DeepSeekClient: AIProviderClient {
    private let baseURL = URL(string: "https://api.deepseek.com")!
    private let session: URLSession
    private let eventReporter: any ImportEventReporting
    private let validationMaxTokens = 16

    init(
        session: URLSession = .shared,
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.session = session
        self.eventReporter = eventReporter
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
                maxTokens: validationMaxTokens,
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
            choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw ProviderConnectionError.invalidResponse("DeepSeek did not return a completed text response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        let provider = "deepseek"
        let candidateIDs = Set(analysisRequest.candidates.map(\.id))
        var repairHint: String?
        var maxTokens = 4_000

        for attemptIndex in 0..<2 {
            let attempt = attemptIndex + 1
            eventReporter.record(
                .providerAttempt(
                    traceID: analysisRequest.traceID,
                    provider: provider,
                    model: model.rawValue,
                    attempt: attempt,
                    maxTokens: maxTokens
                )
            )
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
                            content: ChatScreenshotPrompt.input(
                                for: analysisRequest,
                                repairHint: repairHint
                            )
                        )
                    ],
                    maxTokens: maxTokens,
                    temperature: 0,
                    stream: false,
                    thinking: DeepSeekThinking(type: "disabled"),
                    responseFormat: DeepSeekResponseFormat(type: "json_object")
                )
            )

            let startedAt = Date()
            let (data, response) = try await perform(request)
            let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let httpResponse = response as? HTTPURLResponse
            do {
                try validateHTTPResponse(response, data: data)
            } catch {
                eventReporter.record(
                    .providerResponse(
                        traceID: analysisRequest.traceID,
                        provider: provider,
                        model: model.rawValue,
                        attempt: attempt,
                        durationMilliseconds: duration,
                        httpStatus: httpResponse?.statusCode,
                        requestID: requestID(from: httpResponse),
                        finishReason: nil,
                        byteCount: data.count
                    )
                )
                throw error
            }

            let choice: DeepSeekChoice?
            do {
                choice = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data).choices.first
            } catch {
                choice = nil
            }
            eventReporter.record(
                .providerResponse(
                    traceID: analysisRequest.traceID,
                    provider: provider,
                    model: model.rawValue,
                    attempt: attempt,
                    durationMilliseconds: duration,
                    httpStatus: httpResponse?.statusCode,
                    requestID: requestID(from: httpResponse),
                    finishReason: choice?.finishReason,
                    byteCount: data.count
                )
            )

            do {
                guard let choice else {
                    throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "response.choices")
                }
                return try ChatImportAnalysisDecoder.decode(
                    content: choice.message.content,
                    finishReason: choice.finishReason,
                    candidateIDs: candidateIDs
                )
            } catch let failure as StructuredOutputFailure {
                eventReporter.record(
                    .structuredOutputFailure(
                        traceID: analysisRequest.traceID,
                        provider: provider,
                        attempt: attempt,
                        kind: failure.kind,
                        codingPath: failure.codingPath
                    )
                )
                let error = ProviderConnectionError.structuredOutput(
                    ProviderStructuredOutputError(
                        provider: provider,
                        traceID: analysisRequest.traceID,
                        failure: failure
                    )
                )
                guard attemptIndex == 0, failure.kind.isRetryable else {
                    throw error
                }
                repairHint = ChatImportAnalysisDecoder.repairHint(for: failure)
                if failure.kind == .truncatedResponse {
                    maxTokens = 8_000
                }
            }
        }

        throw ProviderConnectionError.invalidResponse("DeepSeek returned invalid chat data.")
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

    private func requestID(from response: HTTPURLResponse?) -> String? {
        response?.value(forHTTPHeaderField: "x-request-id")
            ?? response?.value(forHTTPHeaderField: "request-id")
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
    let content: String?
}

private struct DeepSeekErrorResponse: Decodable {
    let error: DeepSeekError
}

private struct DeepSeekError: Decodable {
    let message: String
}
