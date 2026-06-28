import Foundation

struct ZAIClient: AIProviderClient {
    enum Region: Sendable {
        case international
        case china

        var platform: ProviderPlatform {
            switch self {
            case .international: .zaiInternational
            case .china: .zhipuChina
            }
        }

        var baseURL: URL {
            switch self {
            case .international:
                URL(string: "https://api.z.ai/api/paas/v4")!
            case .china:
                URL(string: "https://open.bigmodel.cn/api/paas/v4")!
            }
        }

        var providerID: String { platform.rawValue }
    }

    private let region: Region
    private let session: URLSession
    private let eventReporter: any ImportEventReporting

    init(
        region: Region,
        session: URLSession = .shared,
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.region = region
        self.session = session
        self.eventReporter = eventReporter
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        guard model.isSupported(by: region.platform) else {
            throw ProviderConnectionError.unsupportedProvider
        }

        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": "Reply exactly: OK."]]
            ]],
            "max_tokens": 64,
            "thinking": ["type": "disabled"],
            "do_sample": false,
            "stream": false
        ])

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)
        let completion = try decodeResponse(data)
        guard
            let choice = completion.choices.first,
            choice.finishReason == "stop",
            choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw ProviderConnectionError.invalidResponse("\(region.platform.displayName) did not return a completed text response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        guard model.isSupported(by: region.platform) else {
            throw ProviderConnectionError.unsupportedProvider
        }
        let image = try ScreenshotImagePayload(data: analysisRequest.imageData)
        let candidateIDs = Set(analysisRequest.candidates.map(\.id))
        var repairHint: String?
        var maxTokens = 4_000

        for attemptIndex in 0..<2 {
            let attempt = attemptIndex + 1
            eventReporter.record(
                .providerAttempt(
                    traceID: analysisRequest.traceID,
                    provider: region.providerID,
                    model: model.rawValue,
                    attempt: attempt,
                    maxTokens: maxTokens
                )
            )

            let prompt = ChatScreenshotPrompt.input(for: analysisRequest, repairHint: repairHint)
            var request = authorizedRequest(apiKey: apiKey)
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model.rawValue,
                "messages": [
                    ["role": "system", "content": ChatScreenshotPrompt.instructions],
                    [
                        "role": "user",
                        "content": [
                            ["type": "image_url", "image_url": ["url": image.dataURL]],
                            ["type": "text", "text": prompt]
                        ]
                    ]
                ],
                "max_tokens": maxTokens,
                "thinking": ["type": "disabled"],
                "do_sample": false,
                "stream": false,
                "response_format": ["type": "json_object"]
            ])

            let startedAt = Date()
            let (data, response) = try await perform(request)
            let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let httpResponse = response as? HTTPURLResponse
            do {
                try validateHTTPResponse(response, data: data)
            } catch {
                recordResponse(
                    request: analysisRequest,
                    model: model,
                    attempt: attempt,
                    duration: duration,
                    response: httpResponse,
                    finishReason: nil,
                    byteCount: data.count
                )
                throw error
            }

            let completion = try? decodeResponse(data)
            let choice = completion?.choices.first
            recordResponse(
                request: analysisRequest,
                model: model,
                attempt: attempt,
                duration: duration,
                response: httpResponse,
                finishReason: choice?.finishReason,
                byteCount: data.count
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
                        provider: region.providerID,
                        attempt: attempt,
                        kind: failure.kind,
                        codingPath: failure.codingPath
                    )
                )
                let error = ProviderConnectionError.structuredOutput(
                    ProviderStructuredOutputError(
                        provider: region.providerID,
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

        throw ProviderConnectionError.invalidResponse("\(region.platform.displayName) returned invalid chat data.")
    }

    private func authorizedRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: region.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure("Could not reach \(region.platform.displayName). Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse("\(region.platform.displayName) returned an invalid HTTP response.")
        }
        switch response.statusCode {
        case 200..<300: return
        case 401: throw ProviderConnectionError.invalidKey
        case 402: throw ProviderConnectionError.insufficientBalance
        case 429: throw ProviderConnectionError.rateLimited
        case 500..<600: throw ProviderConnectionError.providerUnavailable
        default:
            let message = (try? JSONDecoder().decode(ZAIErrorResponse.self, from: data))?.error.message
            throw ProviderConnectionError.invalidResponse(
                message ?? "\(region.platform.displayName) returned HTTP \(response.statusCode)."
            )
        }
    }

    private func decodeResponse(_ data: Data) throws -> ZAIChatResponse {
        do {
            return try JSONDecoder().decode(ZAIChatResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse("\(region.platform.displayName) returned an unexpected response.")
        }
    }

    private func recordResponse(
        request: ChatScreenshotAnalysisRequest,
        model: ProviderModel,
        attempt: Int,
        duration: Int,
        response: HTTPURLResponse?,
        finishReason: String?,
        byteCount: Int
    ) {
        eventReporter.record(
            .providerResponse(
                traceID: request.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                durationMilliseconds: duration,
                httpStatus: response?.statusCode,
                requestID: response?.value(forHTTPHeaderField: "x-request-id")
                    ?? response?.value(forHTTPHeaderField: "request-id"),
                finishReason: finishReason,
                byteCount: byteCount
            )
        )
    }
}

private struct ZAIChatResponse: Decodable {
    let choices: [ZAIChoice]
}

private struct ZAIChoice: Decodable {
    let message: ZAIMessage
    let finishReason: String

    private enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct ZAIMessage: Decodable {
    let content: String?
}

private struct ZAIErrorResponse: Decodable {
    let error: ZAIError
}

private struct ZAIError: Decodable {
    let message: String
}
