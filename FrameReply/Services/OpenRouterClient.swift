//
//  OpenRouterClient.swift
//  FrameReply
//

import Foundation

struct OpenRouterClient: AIProviderAdapter {
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    private let session: URLSession
    private let eventReporter: any ImportEventReporting

    init(
        session: URLSession = ProviderNetworkSession.make(),
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.session = session
        self.eventReporter = eventReporter
    }

    var platform: ProviderPlatform { .openRouter }

    func modelProfile(for selectedTier: ProviderTier) -> ProviderModelProfile? {
        guard platform.supportedTiers.contains(selectedTier) else { return nil }
        let models = platform.models(for: selectedTier)
        return ProviderModelProfile(
            screenshotAnalysisModel: models.analysis,
            transcriptAnalysisModel: models.replies,
            suggestedReplyModel: models.replies
        )
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        try requireSupported(model)
        let validationSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "status": ["type": "string", "enum": ["ok"]]
            ],
            "required": ["status"],
            "additionalProperties": false
        ]
        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "messages": [
                ["role": "user", "content": "Return status ok."]
            ],
            "max_tokens": ProviderRequestLimits.connectionCheckMaxToken,
            "reasoning": ["effort": "none"],
            "stream": false,
            "response_format": strictResponseFormat(
                name: "connection_validation", schema: validationSchema),
            "provider": routingPolicy
        ])

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)
        let completion = try decodeResponse(data, expectedModel: model)
        guard let choice = completion.choices.first,
            choice.finishReason == "stop",
            let content = choice.message.content,
            let object = try? JSONSerialization.jsonObject(with: Data(content.utf8))
                as? [String: Any],
            Set(object.keys) == Set(["status"]),
            object["status"] as? String == "ok"
        else {
            throw ProviderConnectionError.invalidResponse(
                "OpenRouter did not return the expected validation response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        try requireSupported(model)
        let contract = ChatImportPrompt.contract(for: analysisRequest)
        let images = try analysisRequest.imageDataList.map(ScreenshotImagePayload.init(data:))
        let maxTokens = ProviderRequestLimits.chatImportMaxToken
        let attempt = 1
        let provider = platform.rawValue
        let userContent: [[String: Any]] =
            images.map { image in
                ["type": "image_url", "image_url": ["url": image.dataURL]]
            } + [
                ["type": "text", "text": ChatImportPrompt.input(for: analysisRequest)]
            ]
        eventReporter.record(
            .providerAttempt(
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: attempt,
                maxTokens: maxTokens
            )
        )

        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "system",
                    "content": contract.instructions(for: .nativeJSONSchema)
                ],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": maxTokens,
            "reasoning": ["effort": "none"],
            "stream": false,
            "response_format": strictResponseFormat(
                name: contract.name,
                schema: contract.providerSchema),
            "provider": routingPolicy
        ])

        let startedAt = Date()
        let (data, response) = try await perform(request)
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let httpResponse = response as? HTTPURLResponse
        do {
            try validateHTTPResponse(response, data: data)
        } catch {
            recordResponse(
                traceID: analysisRequest.traceID, model: model, duration: duration,
                response: httpResponse, finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }

        let completion = try decodeResponse(data, expectedModel: model)
        let choice = completion.choices.first
        recordResponse(
            traceID: analysisRequest.traceID, model: model, duration: duration,
            response: httpResponse, finishReason: choice?.finishReason,
            byteCount: data.count, usage: completion.usage)

        do {
            guard let choice else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "response.choices")
            }
            try StrictStructuredOutputValidator.validate(
                content: choice.message.content,
                schema: contract.providerSchema
            )
            let decoded = try ChatImportAnalysisDecoder.decodeResult(
                content: choice.message.content,
                finishReason: choice.finishReason,
                isSharedTranscript: analysisRequest.sharedTranscript != nil,
                candidateIDs: Set(analysisRequest.candidates.map(\.id))
            )
            recordContractValidation(
                contract,
                traceID: analysisRequest.traceID,
                category: decoded.recovered ? "recovered" : "valid"
            )
            return decoded.value
        } catch let failure as StructuredOutputFailure {
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content ?? String(data: data, encoding: .utf8),
                includeRawContent: failure.kind == .schemaMismatch
                    || failure.kind == .invalidJSON
            )
            recordStructuredFailure(
                failure, contract: contract, traceID: analysisRequest.traceID)
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: provider,
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
        try requireSupported(model)
        let contract = SuggestedReplyPrompt.contract(
            for: generationRequest.task,
            appLanguage: generationRequest.appLanguage
        )
        let maxTokens = ProviderRequestLimits.suggestedRepliesMaxToken(
            for: generationRequest.task)
        let attempt = 1
        eventReporter.record(
            .providerAttempt(
                traceID: generationRequest.traceID,
                provider: platform.rawValue,
                model: model.rawValue,
                attempt: attempt,
                maxTokens: maxTokens
            )
        )

        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "messages": [
                [
                    "role": "system",
                    "content": contract.instructions(for: .nativeJSONSchema)
                ],
                ["role": "user", "content": SuggestedReplyPrompt.input(for: generationRequest)]
            ],
            "max_tokens": maxTokens,
            "reasoning": ["effort": "none"],
            "stream": false,
            "response_format": strictResponseFormat(
                name: contract.name,
                schema: contract.providerSchema),
            "provider": routingPolicy
        ])

        let startedAt = Date()
        let (data, response) = try await perform(request)
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let httpResponse = response as? HTTPURLResponse
        do {
            try validateHTTPResponse(response, data: data)
        } catch {
            recordResponse(
                traceID: generationRequest.traceID, model: model, duration: duration,
                response: httpResponse, finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }

        let completion = try decodeResponse(data, expectedModel: model)
        let choice = completion.choices.first
        recordResponse(
            traceID: generationRequest.traceID, model: model, duration: duration,
            response: httpResponse, finishReason: choice?.finishReason,
            byteCount: data.count, usage: completion.usage)

        do {
            guard let choice else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "response.choices")
            }
            try StrictStructuredOutputValidator.validate(
                content: choice.message.content,
                schema: contract.providerSchema
            )
            let decoded = try SuggestedReplyResultDecoder.decodeResult(
                content: choice.message.content,
                finishReason: choice.finishReason,
                task: generationRequest.task
            )
            if decoded.recovered {
                ChatImportDebugLogger.structuredOutputRecovery(
                    decoded.fieldRecoveries,
                    traceID: generationRequest.traceID,
                    provider: platform.rawValue,
                    model: model.rawValue,
                    attempt: attempt,
                    content: choice.message.content
                )
            }
            recordContractValidation(
                contract,
                traceID: generationRequest.traceID,
                category: decoded.recovered ? "recovered" : "valid"
            )
            return decoded.value
        } catch let failure as StructuredOutputFailure {
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: generationRequest.traceID,
                provider: platform.rawValue,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content ?? String(data: data, encoding: .utf8),
                includeRawContent: failure.kind == .schemaMismatch
                    || failure.kind == .invalidJSON
            )
            recordStructuredFailure(
                failure, contract: contract, traceID: generationRequest.traceID)
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: platform.rawValue,
                    traceID: generationRequest.traceID,
                    failure: failure
                )
            )
        }
    }

    private var routingPolicy: [String: Any] {
        [
            "allow_fallbacks": false,
            "require_parameters": true,
            "data_collection": "deny"
        ]
    }

    private func strictResponseFormat(name: String, schema: [String: Any]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": name,
                "strict": true,
                "schema": schema
            ]
        ]
    }

    private func requireSupported(_ model: ProviderModel) throws {
        let supportedModels = Set(
            platform.supportedTiers.flatMap { tier in
                let models = platform.models(for: tier)
                return [models.analysis, models.replies]
            }
        )
        guard supportedModels.contains(model) else {
            throw ProviderConnectionError.unsupportedProvider
        }
    }

    private func authorizedRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FrameReply", forHTTPHeaderField: "X-Title")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try ProviderNetworkSession.validateHTTPS(request, allowedHost: "openrouter.ai")
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure(
                "Could not reach OpenRouter. Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse(
                "OpenRouter returned an invalid HTTP response.")
        }
        switch response.statusCode {
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
        case 400, 403, 404, 422:
            let providerError = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data)
            throw ProviderConnectionError.invalidRequest(
                ProviderInvalidRequestError(
                    provider: platform.rawValue,
                    httpStatus: response.statusCode,
                    providerCode: providerError?.error.code,
                    message:
                        "OpenRouter could not route this request with FrameReply's required model, privacy, and structured-output settings."
                )
            )
        default:
            throw ProviderConnectionError.invalidResponse(
                "OpenRouter returned HTTP \(response.statusCode).")
        }
    }

    private func decodeResponse(
        _ data: Data,
        expectedModel: ProviderModel
    ) throws -> OpenRouterChatResponse {
        let completion: OpenRouterChatResponse
        do {
            completion = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse(
                "OpenRouter returned an unexpected response.")
        }
        guard completion.id.isEmpty == false,
            completion.model == expectedModel.rawValue
        else {
            throw ProviderConnectionError.invalidResponse(
                "OpenRouter returned a response from an unexpected model.")
        }
        return completion
    }

    private func recordResponse(
        traceID: ImportTraceID,
        model: ProviderModel,
        duration: Int,
        response: HTTPURLResponse?,
        finishReason: String?,
        byteCount: Int,
        usage: OpenRouterUsage?
    ) {
        eventReporter.record(
            .providerResponse(
                traceID: traceID,
                provider: platform.rawValue,
                model: model.rawValue,
                attempt: 1,
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

    private func recordContractValidation(
        _ contract: AIOutputContract,
        traceID: ImportTraceID,
        category: String
    ) {
        eventReporter.record(
            .contractValidation(
                traceID: traceID,
                provider: platform.rawValue,
                contract: contract.name,
                version: contract.version,
                attempt: 1,
                category: category
            )
        )
    }

    private func recordStructuredFailure(
        _ failure: StructuredOutputFailure,
        contract: AIOutputContract,
        traceID: ImportTraceID
    ) {
        recordContractValidation(contract, traceID: traceID, category: "fatal")
        eventReporter.record(
            .structuredOutputFailure(
                traceID: traceID,
                provider: platform.rawValue,
                attempt: 1,
                kind: failure.kind,
                codingPath: failure.codingPath
            )
        )
    }
}

private struct OpenRouterChatResponse: Decodable {
    let id: String
    let model: String
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
}

private struct OpenRouterChoice: Decodable {
    let message: OpenRouterMessage
    let finishReason: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterMessage: Decodable {
    let content: String?
}

private struct OpenRouterUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let promptTokenDetails: OpenRouterPromptTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokenDetails = "prompt_tokens_details"
    }
}

private struct OpenRouterPromptTokenDetails: Decodable {
    let cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

private struct OpenRouterErrorResponse: Decodable {
    let error: OpenRouterError
}

private struct OpenRouterError: Decodable {
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .code) {
            code = value
        } else if let value = try? container.decode(Int.self, forKey: .code) {
            code = String(value)
        } else {
            code = nil
        }
    }
}
