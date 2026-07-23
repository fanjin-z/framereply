import Foundation

struct ZAIClient: AIProviderAdapter {
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
        session: URLSession = ProviderNetworkSession.make(),
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.region = region
        self.session = session
        self.eventReporter = eventReporter
    }

    var platform: ProviderPlatform { region.platform }

    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile? {
        let models = platform.models(for: selectedTier)
        return ProviderModelProfile(
            screenshotAnalysisModel: models.analysis,
            transcriptAnalysisModel: models.replies,
            suggestedReplyModel: models.replies
        )
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        guard Self.supportedModels.contains(model) else {
            throw ProviderConnectionError.unsupportedProvider
        }

        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "user",
                    "content": [["type": "text", "text": "Reply exactly: OK."]]
                ]
            ],
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
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) did not return a completed text response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        let supportsModel =
            analysisRequest.sharedTranscript == nil
            ? Self.visionModels.contains(model) : Self.textModels.contains(model)
        guard supportsModel else {
            throw ProviderConnectionError.unsupportedProvider
        }
        let contract = ChatScreenshotPrompt.contract(for: analysisRequest)
        let images = try analysisRequest.imageDataList.map(ScreenshotImagePayload.init(data:))
        let candidateIDs = Set(analysisRequest.candidates.map(\.id))
        let maxTokens = 4_000
        let userContent: [[String: Any]] =
            images.map { image in
                ["type": "image_url", "image_url": ["url": image.dataURL]]
            } + [
                ["type": "text", "text": ChatScreenshotPrompt.input(for: analysisRequest)]
            ]
        let attempt = 1
        eventReporter.record(
            .providerAttempt(
                traceID: analysisRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                maxTokens: maxTokens
            )
        )
        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": contract.instructions(for: .jsonObject)],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": maxTokens,
            "thinking": ["type": "disabled"],
            "do_sample": false,
            "stream": false,
            "response_format": ["type": "json_object"]
        ]
        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response) = try await perform(request)
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let httpResponse = response as? HTTPURLResponse
        do {
            try validateHTTPResponse(response, data: data)
        } catch {
            recordResponse(
                request: analysisRequest, model: model, attempt: attempt,
                duration: duration, response: httpResponse, finishReason: nil,
                byteCount: data.count)
            throw error
        }

        let completion = try decodeResponse(data)
        let choice = completion.choices.first
        if analysisRequest.sharedTranscript == nil {
            ChatImportDebugLogger.responseMetadata(
                traceID: analysisRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content
            )
        }
        recordResponse(
            request: analysisRequest, model: model, attempt: attempt,
            duration: duration, response: httpResponse,
            finishReason: choice?.finishReason, byteCount: data.count,
            usage: completion.usage)

        do {
            guard let choice else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "response.choices")
            }
            let decoded = try ChatImportAnalysisDecoder.decodeResult(
                content: choice.message.content,
                finishReason: choice.finishReason,
                isSharedTranscript: analysisRequest.sharedTranscript != nil,
                candidateIDs: candidateIDs
            )
            if analysisRequest.sharedTranscript == nil {
                ChatImportDebugLogger.normalized(
                    decoded.value,
                    traceID: analysisRequest.traceID,
                    provider: region.providerID,
                    model: model.rawValue,
                    attempt: attempt
                )
            }
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, attempt: attempt,
                category: decoded.recovered ? "recovered" : "valid")
            return decoded.value
        } catch let failure as StructuredOutputFailure {
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, attempt: attempt,
                category: "fatal")
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: analysisRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content ?? String(data: data, encoding: .utf8)
            )
            eventReporter.record(
                .structuredOutputFailure(
                    traceID: analysisRequest.traceID,
                    provider: region.providerID,
                    attempt: attempt,
                    kind: failure.kind,
                    codingPath: failure.codingPath
                )
            )
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: region.providerID,
                    traceID: analysisRequest.traceID,
                    failure: failure
                )
            )
        }
    }

    func generateSuggestedReplies(
        _ generationRequest: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult {
        guard Self.textModels.contains(model) else {
            throw ProviderConnectionError.unsupportedProvider
        }
        let contract = SuggestedReplyPrompt.contract(for: generationRequest.task)

        let maxTokens = 3_200
        let attempt = 1
        eventReporter.record(
            .providerAttempt(
                traceID: generationRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                maxTokens: maxTokens
            )
        )
        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": contract.instructions(for: .jsonObject)],
                ["role": "user", "content": SuggestedReplyPrompt.input(for: generationRequest)]
            ],
            "max_tokens": maxTokens,
            "thinking": ["type": "disabled"],
            "do_sample": false,
            "stream": false,
            "response_format": ["type": "json_object"]
        ]
        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response) = try await perform(request)
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let httpResponse = response as? HTTPURLResponse
        try validateHTTPResponse(response, data: data)

        let completion = try decodeResponse(data)
        let choice = completion.choices.first
        eventReporter.record(
            .providerResponse(
                traceID: generationRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                durationMilliseconds: duration,
                httpStatus: httpResponse?.statusCode,
                requestID: httpResponse?.value(forHTTPHeaderField: "x-request-id")
                    ?? httpResponse?.value(forHTTPHeaderField: "request-id"),
                finishReason: choice?.finishReason,
                byteCount: data.count,
                inputTokens: completion.usage?.promptTokens,
                outputTokens: completion.usage?.completionTokens,
                cachedInputTokens: completion.usage?.promptTokenDetails?.cachedTokens
            )
        )
        do {
            guard let choice else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "response.choices")
            }
            let decoded = try SuggestedReplyResultDecoder.decodeResult(
                content: choice.message.content,
                finishReason: choice.finishReason,
                task: generationRequest.task
            )
            recordContractValidation(
                contract, traceID: generationRequest.traceID, attempt: attempt,
                category: decoded.recovered ? "recovered" : "valid")
            return decoded.value
        } catch let failure as StructuredOutputFailure {
            recordContractValidation(
                contract, traceID: generationRequest.traceID, attempt: attempt,
                category: "fatal")
            eventReporter.record(
                .structuredOutputFailure(
                    traceID: generationRequest.traceID,
                    provider: region.providerID,
                    attempt: attempt,
                    kind: failure.kind,
                    codingPath: failure.codingPath
                )
            )
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: region.providerID,
                    traceID: generationRequest.traceID,
                    failure: failure
                )
            )
        }
    }

    private func recordContractValidation(
        _ contract: AIOutputContract,
        traceID: ImportTraceID,
        attempt: Int,
        category: String
    ) {
        eventReporter.record(
            .contractValidation(
                traceID: traceID, provider: region.providerID, contract: contract.name,
                version: contract.version, attempt: attempt, category: category)
        )
    }

    private static let visionModels: Set<ProviderModel> = [
        .glm46VFlashX, .glm46VFlash, .glm46V
    ]
    private static let textModels: Set<ProviderModel> = [
        .glm47FlashX, .glm47Flash, .glm47
    ]
    private static let supportedModels = visionModels.union(textModels)

    private func authorizedRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: region.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let host = region.baseURL.host else {
            throw ProviderConnectionError.networkFailure(
                "The provider request was blocked because its destination was invalid."
            )
        }
        try ProviderNetworkSession.validateHTTPS(request, allowedHost: host)
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure(
                "Could not reach \(region.platform.displayName). Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) returned an invalid HTTP response.")
        }
        switch response.statusCode {
        case 200..<300: return
        case 401: throw ProviderConnectionError.invalidKey
        case 402: throw ProviderConnectionError.insufficientBalance
        case 429: throw ProviderConnectionError.rateLimited
        case 500..<600: throw ProviderConnectionError.providerUnavailable
        case 400, 422:
            let providerError = try? JSONDecoder().decode(ZAIErrorResponse.self, from: data)
            throw ProviderConnectionError.invalidRequest(
                ProviderInvalidRequestError(
                    provider: region.providerID,
                    httpStatus: response.statusCode,
                    providerCode: providerError?.error.code,
                    message: "\(region.platform.displayName) rejected an API parameter."
                )
            )
        default:
            let message = (try? JSONDecoder().decode(ZAIErrorResponse.self, from: data))?.error
                .message
            throw ProviderConnectionError.invalidResponse(
                message ?? "\(region.platform.displayName) returned HTTP \(response.statusCode)."
            )
        }
    }

    private func decodeResponse(_ data: Data) throws -> ZAIChatResponse {
        do {
            return try JSONDecoder().decode(ZAIChatResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) returned an unexpected response.")
        }
    }

    private func recordResponse(
        request: ChatScreenshotAnalysisRequest,
        model: ProviderModel,
        attempt: Int,
        duration: Int,
        response: HTTPURLResponse?,
        finishReason: String?,
        byteCount: Int,
        usage: ZAIUsage? = nil
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
                byteCount: byteCount,
                inputTokens: usage?.promptTokens,
                outputTokens: usage?.completionTokens,
                cachedInputTokens: usage?.promptTokenDetails?.cachedTokens
            )
        )
    }
}

private struct ZAIChatResponse: Decodable {
    let choices: [ZAIChoice]
    let usage: ZAIUsage?
}

private struct ZAIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let promptTokenDetails: ZAIPromptTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokenDetails = "prompt_tokens_details"
    }
}

private struct ZAIPromptTokenDetails: Decodable {
    let cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
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
    let code: String?
    let message: String

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        if let value = try? container.decode(String.self, forKey: .code) {
            code = value
        } else if let value = try? container.decode(Int.self, forKey: .code) {
            code = String(value)
        } else {
            code = nil
        }
    }
}
