//
//  OpenAIClient.swift
//  FrameReply
//

import Foundation

struct OpenAIClient: AIProviderAdapter {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let session: URLSession
    private let eventReporter: any ImportEventReporting
    private let validationMaxOutputTokens = 16

    init(
        session: URLSession = ProviderNetworkSession.make(),
        eventReporter: any ImportEventReporting = OSLogImportEventReporter()
    ) {
        self.session = session
        self.eventReporter = eventReporter
    }

    var platform: ProviderPlatform { .openAI }

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
        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: model.rawValue,
                input: "Reply exactly: OK.",
                maxOutputTokens: validationMaxOutputTokens,
                reasoning: OpenAIReasoning(effort: "none")
            )
        )

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)

        let completion: OpenAIResponse
        do {
            completion = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse("OpenAI returned an unexpected response.")
        }

        guard
            completion.id.isEmpty == false,
            completion.status == "completed",
            completion.hasTextOutput
        else {
            throw ProviderConnectionError.invalidResponse(
                "OpenAI did not return a completed text response.")
        }
    }

    func analyzeChatScreenshot(
        _ analysisRequest: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        guard Self.supportedModels.contains(model) else {
            throw ProviderConnectionError.unsupportedProvider
        }
        let contract = ChatScreenshotPrompt.contract(for: analysisRequest)
        let images = try analysisRequest.imageDataList.map(ScreenshotImagePayload.init(data:))
        let provider = "openai"
        eventReporter.record(
            .providerAttempt(
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: 1,
                maxTokens: 4_000
            )
        )
        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let content: [[String: Any]] =
            images.map { image in
                [
                    "type": "input_image",
                    "image_url": image.dataURL,
                    "detail": "high"
                ]
            } + [
                [
                    "type": "input_text",
                    "text": ChatScreenshotPrompt.input(for: analysisRequest)
                ]
            ]
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "model": model.rawValue,
                "instructions": contract.instructions(for: .strictJSONSchema),
                "input": [
                    [
                        "role": "user",
                        "content": content
                    ]
                ],
                "max_output_tokens": 4_000,
                "reasoning": ["effort": "none"],
                "store": false,
                "prompt_cache_key": "\(contract.name)-v\(contract.version)-\(model.rawValue)",
                "text": [
                    "format": [
                        "type": "json_schema",
                        "name": contract.name,
                        "strict": true,
                        "schema": contract.schema
                    ]
                ]
            ]
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
                    attempt: 1,
                    durationMilliseconds: duration,
                    httpStatus: httpResponse?.statusCode,
                    requestID: requestID(from: httpResponse),
                    finishReason: nil,
                    byteCount: data.count,
                    inputTokens: nil,
                    outputTokens: nil,
                    cachedInputTokens: nil
                )
            )
            throw error
        }

        let completion: OpenAIResponse
        do {
            completion = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            let failure = StructuredOutputFailure(kind: .schemaMismatch, codingPath: "response")
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: 1,
                finishReason: nil,
                content: String(data: data, encoding: .utf8)
            )
            recordStructuredFailure(
                failure,
                request: analysisRequest,
                model: model,
                duration: duration,
                response: httpResponse,
                responseByteCount: data.count,
                finishReason: nil
            )
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: provider,
                    traceID: analysisRequest.traceID,
                    failure: failure
                )
            )
        }

        eventReporter.record(
            .providerResponse(
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: 1,
                durationMilliseconds: duration,
                httpStatus: httpResponse?.statusCode,
                requestID: requestID(from: httpResponse),
                finishReason: completion.status,
                byteCount: data.count,
                inputTokens: completion.usage?.inputTokens,
                outputTokens: completion.usage?.outputTokens,
                cachedInputTokens: completion.usage?.inputTokenDetails?.cachedTokens
            )
        )

        guard completion.status == "completed" else {
            if completion.incompleteDetails?.reason == "content_filter" {
                recordContractValidation(
                    contract, traceID: analysisRequest.traceID, provider: provider,
                    attempt: 1, category: "content_filter")
                throw ProviderConnectionError.invalidResponse(
                    "OpenAI filtered the import response for safety.")
            }
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, provider: provider,
                attempt: 1, category: StructuredOutputFailureKind.truncatedResponse.rawValue)
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: provider,
                    traceID: analysisRequest.traceID,
                    failure: StructuredOutputFailure(
                        kind: .truncatedResponse, codingPath: "response.status")
                )
            )
        }
        if completion.refusal != nil {
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, provider: provider,
                attempt: 1, category: "refusal")
            throw ProviderConnectionError.invalidResponse("OpenAI refused the import request.")
        }
        if analysisRequest.sharedTranscript == nil {
            ChatImportDebugLogger.responseMetadata(
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: 1,
                finishReason: completion.status,
                content: completion.outputText
            )
        }
        do {
            let analysis = try ChatImportAnalysisDecoder.decode(
                content: completion.outputText,
                finishReason: nil,
                isSharedTranscript: analysisRequest.sharedTranscript != nil,
                candidateIDs: Set(analysisRequest.candidates.map(\.id))
            )
            if analysisRequest.sharedTranscript == nil {
                ChatImportDebugLogger.normalized(
                    analysis,
                    traceID: analysisRequest.traceID,
                    provider: provider,
                    model: model.rawValue,
                    attempt: 1
                )
            }
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, provider: provider,
                attempt: 1, category: "valid")
            return analysis
        } catch let failure as StructuredOutputFailure {
            recordContractValidation(
                contract, traceID: analysisRequest.traceID, provider: provider,
                attempt: 1, category: failure.kind.rawValue)
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: analysisRequest.traceID,
                provider: provider,
                model: model.rawValue,
                attempt: 1,
                finishReason: completion.status,
                content: completion.outputText
            )
            eventReporter.record(
                .structuredOutputFailure(
                    traceID: analysisRequest.traceID,
                    provider: provider,
                    attempt: 1,
                    kind: failure.kind,
                    codingPath: failure.codingPath
                )
            )
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
        guard Self.supportedModels.contains(model) else {
            throw ProviderConnectionError.unsupportedProvider
        }
        let contract = SuggestedReplyPrompt.contract(for: generationRequest.task)
        let maxTokens = 3_200
        eventReporter.record(
            .providerAttempt(
                traceID: generationRequest.traceID,
                provider: "openai",
                model: model.rawValue,
                attempt: 1,
                maxTokens: maxTokens
            )
        )

        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue,
            "instructions": contract.instructions(for: .strictJSONSchema),
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": SuggestedReplyPrompt.input(for: generationRequest)
                        ]
                    ]
                ]
            ],
            "max_output_tokens": maxTokens,
            "reasoning": ["effort": "none"],
            "store": false,
            "prompt_cache_key": "\(contract.name)-v\(contract.version)-\(model.rawValue)",
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": contract.name,
                    "strict": true,
                    "schema": contract.schema
                ]
            ]
        ])

        let startedAt = Date()
        let (data, response) = try await perform(request)
        let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let httpResponse = response as? HTTPURLResponse
        do {
            try validateHTTPResponse(response, data: data)
        } catch {
            eventReporter.record(
                .providerResponse(
                    traceID: generationRequest.traceID,
                    provider: "openai",
                    model: model.rawValue,
                    attempt: 1,
                    durationMilliseconds: duration,
                    httpStatus: httpResponse?.statusCode,
                    requestID: requestID(from: httpResponse),
                    finishReason: nil,
                    byteCount: data.count,
                    inputTokens: nil,
                    outputTokens: nil,
                    cachedInputTokens: nil
                )
            )
            throw error
        }

        let completion: OpenAIResponse
        do {
            completion = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse(
                "OpenAI returned an unexpected reply response.")
        }
        eventReporter.record(
            .providerResponse(
                traceID: generationRequest.traceID,
                provider: "openai",
                model: model.rawValue,
                attempt: 1,
                durationMilliseconds: duration,
                httpStatus: httpResponse?.statusCode,
                requestID: requestID(from: httpResponse),
                finishReason: completion.status,
                byteCount: data.count,
                inputTokens: completion.usage?.inputTokens,
                outputTokens: completion.usage?.outputTokens,
                cachedInputTokens: completion.usage?.inputTokenDetails?.cachedTokens
            )
        )

        do {
            guard completion.status == "completed" else {
                if completion.incompleteDetails?.reason == "content_filter" {
                    recordContractValidation(
                        contract, traceID: generationRequest.traceID, provider: "openai",
                        attempt: 1, category: "content_filter")
                    throw ProviderConnectionError.invalidResponse(
                        "OpenAI filtered the reply response for safety.")
                }
                throw StructuredOutputFailure(
                    kind: .truncatedResponse, codingPath: "response.status")
            }
            if completion.refusal != nil {
                recordContractValidation(
                    contract, traceID: generationRequest.traceID, provider: "openai",
                    attempt: 1, category: "refusal")
                throw ProviderConnectionError.invalidResponse("OpenAI refused the reply request.")
            }
            let result = try SuggestedReplyResultDecoder.decode(
                content: completion.outputText,
                finishReason: nil,
                task: generationRequest.task,
                historySummaryFallback: summaryFallback(for: generationRequest)
            )
            recordContractValidation(
                contract, traceID: generationRequest.traceID, provider: "openai",
                attempt: 1, category: "valid")
            return result
        } catch let failure as StructuredOutputFailure {
            recordContractValidation(
                contract, traceID: generationRequest.traceID, provider: "openai",
                attempt: 1, category: failure.kind.rawValue)
            eventReporter.record(
                .structuredOutputFailure(
                    traceID: generationRequest.traceID,
                    provider: "openai",
                    attempt: 1,
                    kind: failure.kind,
                    codingPath: failure.codingPath
                )
            )
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: "openai",
                    traceID: generationRequest.traceID,
                    failure: failure
                )
            )
        }
    }

    private static let supportedModels: Set<ProviderModel> = [.gpt56Luna, .gpt56Terra, .gpt56Sol]

    private func summaryFallback(for request: SuggestedReplyGenerationRequest) -> String? {
        if request.summaryMode == .unchanged {
            return request.existingHistorySummary
        }
        return request.olderMessagesToSummarize.isEmpty ? "" : nil
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try ProviderNetworkSession.validateHTTPS(request, allowedHost: "api.openai.com")
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure(
                "Could not reach OpenAI. Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse(
                "OpenAI returned an invalid HTTP response.")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw ProviderConnectionError.invalidKey
        case 429:
            if openAIError(from: data)?.code == "insufficient_quota" {
                throw ProviderConnectionError.insufficientBalance
            }
            throw ProviderConnectionError.rateLimited
        case 500..<600:
            throw ProviderConnectionError.providerUnavailable
        default:
            throw ProviderConnectionError.invalidResponse(
                "OpenAI rejected the request with HTTP \(httpResponse.statusCode)."
            )
        }
    }

    private func openAIError(from data: Data) -> OpenAIError? {
        try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data).error
    }

    private func requestID(from response: HTTPURLResponse?) -> String? {
        response?.value(forHTTPHeaderField: "x-request-id")
            ?? response?.value(forHTTPHeaderField: "request-id")
    }

    private func recordContractValidation(
        _ contract: AIOutputContract,
        traceID: ImportTraceID,
        provider: String,
        attempt: Int,
        category: String
    ) {
        eventReporter.record(
            .contractValidation(
                traceID: traceID, provider: provider, contract: contract.name,
                version: contract.version, attempt: attempt, category: category)
        )
    }

    private func recordStructuredFailure(
        _ failure: StructuredOutputFailure,
        request: ChatScreenshotAnalysisRequest,
        model: ProviderModel,
        duration: Int,
        response: HTTPURLResponse?,
        responseByteCount: Int,
        finishReason: String?
    ) {
        eventReporter.record(
            .providerResponse(
                traceID: request.traceID,
                provider: "openai",
                model: model.rawValue,
                attempt: 1,
                durationMilliseconds: duration,
                httpStatus: response?.statusCode,
                requestID: requestID(from: response),
                finishReason: finishReason,
                byteCount: responseByteCount,
                inputTokens: nil,
                outputTokens: nil,
                cachedInputTokens: nil
            )
        )
        eventReporter.record(
            .structuredOutputFailure(
                traceID: request.traceID,
                provider: "openai",
                attempt: 1,
                kind: failure.kind,
                codingPath: failure.codingPath
            )
        )
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let input: String
    let maxOutputTokens: Int
    let reasoning: OpenAIReasoning

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
        case reasoning
    }
}

private struct OpenAIReasoning: Encodable {
    let effort: String
}

private struct OpenAIResponse: Decodable {
    let id: String
    let status: String
    let output: [OpenAIOutput]
    let usage: OpenAIUsage?
    let incompleteDetails: OpenAIIncompleteDetails?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case output
        case usage
        case incompleteDetails = "incomplete_details"
    }

    var hasTextOutput: Bool {
        output.contains { item in
            item.type == "message"
                && item.content.contains { content in
                    content.type == "output_text"
                        && content.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            == false
                }
        }
    }

    var outputText: String? {
        output
            .first(where: { $0.type == "message" })?
            .content.first(where: { $0.type == "output_text" })?
            .text
    }

    var refusal: String? {
        output
            .first(where: { $0.type == "message" })?
            .content.first(where: { $0.type == "refusal" })?
            .refusal
    }
}

private struct OpenAIIncompleteDetails: Decodable {
    let reason: String?
}

private struct OpenAIUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let inputTokenDetails: OpenAIInputTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputTokenDetails = "input_tokens_details"
    }
}

private struct OpenAIInputTokenDetails: Decodable {
    let cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

private struct OpenAIOutput: Decodable {
    let type: String
    let content: [OpenAIOutputContent]

    private enum CodingKeys: String, CodingKey {
        case type
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decodeIfPresent([OpenAIOutputContent].self, forKey: .content) ?? []
    }
}

private struct OpenAIOutputContent: Decodable {
    let type: String
    let text: String?
    let refusal: String?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let code: String?
    let message: String
}
