//
//  MiniMaxClient.swift
//  FrameReply
//

import Foundation

struct MiniMaxClient: AIProviderAdapter {
    enum Region: Sendable {
        case international
        case china

        var platform: ProviderPlatform {
            switch self {
            case .international: .miniMaxInternational
            case .china: .miniMaxChina
            }
        }

        var baseURL: URL {
            switch self {
            case .international:
                URL(string: "https://api.minimax.io/v1")!
            case .china:
                URL(string: "https://api.minimaxi.com/v1")!
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
        guard platform.supportedTiers.contains(selectedTier) else { return nil }
        return ProviderModelProfile(
            screenshotAnalysisModel: .miniMaxM3,
            transcriptAnalysisModel: .miniMaxM3,
            suggestedReplyModel: .miniMaxM3
        )
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        try requireSupported(model)
        var request = authorizedRequest(apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            model: model,
            messages: [["role": "user", "content": "Reply exactly: OK."]],
            maxCompletionTokens: 64
        ))

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)
        let completion = try decodeResponse(data)
        try validateProviderResponse(completion, httpStatus: (response as? HTTPURLResponse)?.statusCode)
        try validateReturnedModel(completion.model, requestedModel: model)
        try rejectFilteredCompletion(
            completion.choices?.first?.finishReason,
            httpStatus: (response as? HTTPURLResponse)?.statusCode)
        guard
            let choice = completion.choices?.first,
            choice.finishReason == "stop",
            choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) did not return a completed text response."
            )
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
        let candidateIDs = Set(analysisRequest.candidates.map(\.id))
        let maxTokens = 4_000
        let userContent: [[String: Any]] = images.map { image in
            [
                "type": "image_url",
                "image_url": ["url": image.dataURL, "detail": "high"]
            ]
        } + [["type": "text", "text": ChatImportPrompt.input(for: analysisRequest)]]
        let userMessageContent: Any =
            analysisRequest.sharedTranscript == nil
            ? userContent
            : ChatImportPrompt.input(for: analysisRequest)
        let attempt = 1

        eventReporter.record(.providerAttempt(
            traceID: analysisRequest.traceID,
            provider: region.providerID,
            model: model.rawValue,
            attempt: attempt,
            maxTokens: maxTokens
        ))

        let body = requestBody(
            model: model,
            messages: [
                ["role": "system", "content": providerInstructions(for: contract)],
                ["role": "user", "content": userMessageContent]
            ],
            maxCompletionTokens: maxTokens
        )
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
                traceID: analysisRequest.traceID, model: model, attempt: attempt,
                duration: duration, response: httpResponse, responseID: nil,
                finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }

        let completion: MiniMaxChatResponse
        do {
            completion = try decodeResponse(data)
        } catch {
            recordResponse(
                traceID: analysisRequest.traceID, model: model, attempt: attempt,
                duration: duration, response: httpResponse, responseID: nil,
                finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }
        let choice = completion.choices?.first
        recordResponse(
            traceID: analysisRequest.traceID, model: model, attempt: attempt,
            duration: duration, response: httpResponse, responseID: completion.id,
            finishReason: choice?.finishReason, byteCount: data.count, usage: completion.usage)
        try validateProviderResponse(completion, httpStatus: httpResponse?.statusCode)
        try validateReturnedModel(completion.model, requestedModel: model)
        try rejectFilteredCompletion(choice?.finishReason, httpStatus: httpResponse?.statusCode)

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

        do {
            guard let choice else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "response.choices")
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
                contract, traceID: analysisRequest.traceID, attempt: attempt, category: "fatal")
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: analysisRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content ?? String(data: data, encoding: .utf8),
                includeRawContent: failure.kind == .schemaMismatch
            )
            eventReporter.record(.structuredOutputFailure(
                traceID: analysisRequest.traceID,
                provider: region.providerID,
                attempt: attempt,
                kind: failure.kind,
                codingPath: failure.codingPath
            ))
            throw ProviderConnectionError.structuredOutput(ProviderStructuredOutputError(
                provider: region.providerID,
                traceID: analysisRequest.traceID,
                failure: failure
            ))
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
        let maxTokens = 3_200
        let attempt = 1

        eventReporter.record(.providerAttempt(
            traceID: generationRequest.traceID,
            provider: region.providerID,
            model: model.rawValue,
            attempt: attempt,
            maxTokens: maxTokens
        ))

        let body = requestBody(
            model: model,
            messages: [
                ["role": "system", "content": providerInstructions(for: contract)],
                ["role": "user", "content": SuggestedReplyPrompt.input(for: generationRequest)]
            ],
            maxCompletionTokens: maxTokens
        )
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
                traceID: generationRequest.traceID, model: model, attempt: attempt,
                duration: duration, response: httpResponse, responseID: nil,
                finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }

        let completion: MiniMaxChatResponse
        do {
            completion = try decodeResponse(data)
        } catch {
            recordResponse(
                traceID: generationRequest.traceID, model: model, attempt: attempt,
                duration: duration, response: httpResponse, responseID: nil,
                finishReason: nil, byteCount: data.count, usage: nil)
            throw error
        }
        let choice = completion.choices?.first
        recordResponse(
            traceID: generationRequest.traceID, model: model, attempt: attempt,
            duration: duration, response: httpResponse, responseID: completion.id,
            finishReason: choice?.finishReason, byteCount: data.count, usage: completion.usage)
        try validateProviderResponse(completion, httpStatus: httpResponse?.statusCode)
        try validateReturnedModel(completion.model, requestedModel: model)
        try rejectFilteredCompletion(choice?.finishReason, httpStatus: httpResponse?.statusCode)

        do {
            guard let choice else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "response.choices")
            }
            let decoded = try SuggestedReplyResultDecoder.decodeResult(
                content: choice.message.content,
                finishReason: choice.finishReason,
                task: generationRequest.task
            )
            ChatImportDebugLogger.fieldRecoveries(
                decoded.fieldRecoveries,
                traceID: generationRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt
            )
            recordContractValidation(
                contract, traceID: generationRequest.traceID, attempt: attempt,
                category: decoded.recovered ? "recovered" : "valid")
            return decoded.value
        } catch let failure as StructuredOutputFailure {
            recordContractValidation(
                contract, traceID: generationRequest.traceID, attempt: attempt, category: "fatal")
            ChatImportDebugLogger.structuredOutputFailure(
                failure,
                traceID: generationRequest.traceID,
                provider: region.providerID,
                model: model.rawValue,
                attempt: attempt,
                finishReason: choice?.finishReason,
                content: choice?.message.content ?? String(data: data, encoding: .utf8),
                includeRawContent: failure.kind == .schemaMismatch
            )
            eventReporter.record(.structuredOutputFailure(
                traceID: generationRequest.traceID,
                provider: region.providerID,
                attempt: attempt,
                kind: failure.kind,
                codingPath: failure.codingPath
            ))
            throw ProviderConnectionError.structuredOutput(ProviderStructuredOutputError(
                provider: region.providerID,
                traceID: generationRequest.traceID,
                failure: failure
            ))
        }
    }

    private func requireSupported(_ model: ProviderModel) throws {
        guard model == .miniMaxM3 else {
            throw ProviderConnectionError.unsupportedProvider
        }
    }

    private func providerInstructions(for contract: AIOutputContract) -> String {
        """
        \(contract.instructions(for: .promptedJSONObject))
        Return the JSON object as raw text only. Do not use Markdown, code fences, or explanatory prose. The first non-whitespace character must be { and the last non-whitespace character must be }.
        """
    }

    private func requestBody(
        model: ProviderModel,
        messages: [[String: Any]],
        maxCompletionTokens: Int
    ) -> [String: Any] {
        [
            "model": model.rawValue,
            "service_tier": "standard",
            "thinking": ["type": "disabled"],
            "temperature": 0,
            "stream": false,
            "max_completion_tokens": maxCompletionTokens,
            "messages": messages
        ]
    }

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
                "The provider request was blocked because its destination was invalid.")
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

        if let completion = try? JSONDecoder().decode(MiniMaxChatResponse.self, from: data),
            let statusCode = completion.baseResponse?.statusCode,
            statusCode != 0
        {
            try throwProviderStatus(
                statusCode, message: completion.baseResponse?.statusMessage,
                httpStatus: response.statusCode)
        }

        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw ProviderConnectionError.invalidKey
        case 402: throw ProviderConnectionError.insufficientBalance
        case 429: throw ProviderConnectionError.rateLimited
        case 500..<600: throw ProviderConnectionError.providerUnavailable
        case 400, 404, 422:
            let error = try? JSONDecoder().decode(MiniMaxChatResponse.self, from: data)
            throw ProviderConnectionError.invalidRequest(ProviderInvalidRequestError(
                provider: region.providerID,
                httpStatus: response.statusCode,
                providerCode: error?.error?.code,
                message: "\(region.platform.displayName) rejected an API parameter."
            ))
        default:
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) returned HTTP \(response.statusCode).")
        }
    }

    private func decodeResponse(_ data: Data) throws -> MiniMaxChatResponse {
        do {
            return try JSONDecoder().decode(MiniMaxChatResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) returned an unexpected response.")
        }
    }

    private func validateProviderResponse(
        _ response: MiniMaxChatResponse,
        httpStatus: Int?
    ) throws {
        if let statusCode = response.baseResponse?.statusCode, statusCode != 0 {
            try throwProviderStatus(
                statusCode, message: response.baseResponse?.statusMessage,
                httpStatus: httpStatus ?? 200)
        }
        if response.inputSensitive == true || response.outputSensitive == true {
            throw ProviderConnectionError.invalidRequest(ProviderInvalidRequestError(
                provider: region.providerID,
                httpStatus: httpStatus ?? 200,
                providerCode: response.inputSensitive == true ? "1026" : "1027",
                message: "\(region.platform.displayName) rejected sensitive content."
            ))
        }
    }

    private func validateReturnedModel(
        _ returnedModel: String?,
        requestedModel: ProviderModel
    ) throws {
        guard returnedModel == requestedModel.rawValue else {
            throw ProviderConnectionError.invalidResponse(
                "\(region.platform.displayName) returned a response from an unexpected model.")
        }
    }

    private func rejectFilteredCompletion(_ finishReason: String?, httpStatus: Int?) throws {
        guard finishReason == "content_filter" else { return }
        throw ProviderConnectionError.invalidRequest(ProviderInvalidRequestError(
            provider: region.providerID,
            httpStatus: httpStatus ?? 200,
            providerCode: "content_filter",
            message: "\(region.platform.displayName) filtered the response."
        ))
    }

    private func throwProviderStatus(
        _ statusCode: Int,
        message: String?,
        httpStatus: Int
    ) throws {
        switch statusCode {
        case 1004:
            throw ProviderConnectionError.invalidKey
        case 1008:
            throw ProviderConnectionError.insufficientBalance
        case 1002, 1041:
            throw ProviderConnectionError.rateLimited
        case 1000, 1001, 1013, 1024, 1033:
            throw ProviderConnectionError.providerUnavailable
        case 1026, 1027, 1039, 2013:
            throw ProviderConnectionError.invalidRequest(ProviderInvalidRequestError(
                provider: region.providerID,
                httpStatus: httpStatus,
                providerCode: String(statusCode),
                message: "\(region.platform.displayName) rejected the request."
            ))
        default:
            throw ProviderConnectionError.invalidResponse(
                message ?? "\(region.platform.displayName) returned provider error \(statusCode).")
        }
    }

    private func recordContractValidation(
        _ contract: AIOutputContract,
        traceID: ImportTraceID,
        attempt: Int,
        category: String
    ) {
        eventReporter.record(.contractValidation(
            traceID: traceID,
            provider: region.providerID,
            contract: contract.name,
            version: contract.version,
            attempt: attempt,
            category: category
        ))
    }

    private func recordResponse(
        traceID: ImportTraceID,
        model: ProviderModel,
        attempt: Int,
        duration: Int,
        response: HTTPURLResponse?,
        responseID: String?,
        finishReason: String?,
        byteCount: Int,
        usage: MiniMaxUsage?
    ) {
        eventReporter.record(.providerResponse(
            traceID: traceID,
            provider: region.providerID,
            model: model.rawValue,
            attempt: attempt,
            durationMilliseconds: duration,
            httpStatus: response?.statusCode,
            requestID: response?.value(forHTTPHeaderField: "x-request-id")
                ?? response?.value(forHTTPHeaderField: "request-id")
                ?? responseID,
            finishReason: finishReason,
            byteCount: byteCount,
            inputTokens: usage?.promptTokens,
            outputTokens: usage?.completionTokens,
            cachedInputTokens: usage?.promptTokenDetails?.cachedTokens
        ))
    }
}

private struct MiniMaxChatResponse: Decodable {
    let id: String?
    let model: String?
    let choices: [MiniMaxChoice]?
    let usage: MiniMaxUsage?
    let baseResponse: MiniMaxBaseResponse?
    let inputSensitive: Bool?
    let outputSensitive: Bool?
    let error: MiniMaxError?

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case choices
        case usage
        case baseResponse = "base_resp"
        case inputSensitive = "input_sensitive"
        case outputSensitive = "output_sensitive"
        case error
    }
}

private struct MiniMaxChoice: Decodable {
    let message: MiniMaxMessage
    let finishReason: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct MiniMaxMessage: Decodable {
    let content: String?
}

private struct MiniMaxUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let promptTokenDetails: MiniMaxPromptTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptTokenDetails = "prompt_tokens_details"
    }
}

private struct MiniMaxPromptTokenDetails: Decodable {
    let cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

private struct MiniMaxBaseResponse: Decodable {
    let statusCode: Int?
    let statusMessage: String?

    private enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMessage = "status_msg"
    }
}

private struct MiniMaxError: Decodable {
    let code: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try? container.decode(String.self, forKey: .message)
        if let value = try? container.decode(String.self, forKey: .code) {
            code = value
        } else if let value = try? container.decode(Int.self, forKey: .code) {
            code = String(value)
        } else {
            code = nil
        }
    }
}
