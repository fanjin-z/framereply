import Foundation
import XCTest

@testable import FrameReply

final class ProviderValidatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    @MainActor
    func testProvidersUseOneSelectedModelProbe() async throws {
        AnalysisURLProtocolStub.stub(
            statusCode: 200,
            body:
                #"{"id":"resp_1","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
        )

        try await OpenAIClient(session: makeSession()).validate(
            apiKey: "open-key",
            model: .gpt56Luna
        )

        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        let openAIRequest = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        XCTAssertEqual(openAIRequest.url?.path, "/v1/responses")
        XCTAssertEqual(
            openAIRequest.value(forHTTPHeaderField: "Authorization"),
            "Bearer open-key"
        )

        let openAIBody = try jsonBody(openAIRequest)
        XCTAssertEqual(openAIBody["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual(openAIBody["input"] as? String, "Reply exactly: OK.")
        XCTAssertEqual(openAIBody["max_output_tokens"] as? Int, 16)
        XCTAssertEqual(
            (openAIBody["reasoning"] as? [String: Any])?["effort"] as? String,
            "none"
        )

        AnalysisURLProtocolStub.reset()
        AnalysisURLProtocolStub.stub(
            statusCode: 200,
            body:
                #"{"id":"gen_1","model":"qwen/qwen3.7-plus","choices":[{"message":{"content":"{\"status\":\"ok\"}"},"finish_reason":"stop"}]}"#
        )

        try await OpenRouterClient(session: makeSession()).validate(
            apiKey: "sk-or-test",
            model: .qwen37Plus
        )

        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        let openRouterRequest = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        let openRouterBody = try jsonBody(openRouterRequest)
        XCTAssertEqual(openRouterBody["model"] as? String, "qwen/qwen3.7-plus")
        let routing = try XCTUnwrap(openRouterBody["provider"] as? [String: Any])
        XCTAssertEqual(routing["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(routing["require_parameters"] as? Bool, true)
        XCTAssertEqual(routing["data_collection"] as? String, "deny")
        let format = try XCTUnwrap(openRouterBody["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)

        for (region, host) in [
            (MiniMaxClient.Region.international, "api.minimax.io"),
            (.china, "api.minimaxi.com")
        ] {
            AnalysisURLProtocolStub.reset()
            AnalysisURLProtocolStub.stub(
                statusCode: 200,
                body:
                    #"{"id":"m3_1","model":"MiniMax-M3","choices":[{"message":{"content":"OK"},"finish_reason":"stop"}],"base_resp":{"status_code":0,"status_msg":"success"}}"#
            )

            try await MiniMaxClient(region: region, session: makeSession()).validate(
                apiKey: "minimax-key", model: .miniMaxM3)

            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, host)
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"), "Bearer minimax-key")
            let body = try jsonBody(request)
            XCTAssertEqual(body["model"] as? String, "MiniMax-M3")
            XCTAssertEqual(body["service_tier"] as? String, "standard")
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            XCTAssertEqual(body["temperature"] as? Int, 0)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 64)
            XCTAssertNil(body["response_format"])
        }
    }

    @MainActor
    func testProvidersRejectMalformedResponses() async {
        await assertInvalidResponse(
            from: OpenAIClient(session: makeSession()),
            model: .gpt56Luna,
            body:
                #"{"id":"resp_1","status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
        )
        await assertInvalidResponse(
            from: OpenRouterClient(session: makeSession()),
            model: .qwen37Plus,
            body:
                #"{"id":"gen_1","model":"openrouter/auto","choices":[{"message":{"content":"{\"status\":\"ok\"}"},"finish_reason":"stop"}]}"#
        )
        await assertInvalidResponse(
            from: MiniMaxClient(region: .international, session: makeSession()),
            model: .miniMaxM3,
            body:
                #"{"id":"m3_1","model":"MiniMax-M2.7","choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#
        )
    }

    @MainActor
    func testProvidersMapHTTPFailures() async {
        await assertHTTPError(
            .invalidKey, statusCode: 401, validator: OpenAIClient(session: makeSession()),
            model: .gpt56Luna)
        await assertHTTPError(
            .insufficientBalance,
            statusCode: 429,
            body: #"{"error":{"code":"insufficient_quota","message":"No quota"}}"#,
            validator: OpenAIClient(session: makeSession()),
            model: .gpt56Luna
        )
        await assertHTTPError(
            .rateLimited,
            statusCode: 429,
            body: #"{"error":{"code":"rate_limit_exceeded","message":"Slow down"}}"#,
            validator: OpenAIClient(session: makeSession()),
            model: .gpt56Luna
        )
        await assertHTTPError(
            .providerUnavailable, statusCode: 500, validator: OpenAIClient(session: makeSession()),
            model: .gpt56Luna)
        let openRouter = OpenRouterClient(session: makeSession())
        await assertHTTPError(
            .invalidKey, statusCode: 401, validator: openRouter, model: .qwen37Plus)
        await assertHTTPError(
            .insufficientBalance, statusCode: 402, validator: openRouter, model: .qwen37Plus)
        await assertHTTPError(
            .rateLimited, statusCode: 429, validator: openRouter, model: .qwen37Plus)
        await assertHTTPError(
            .providerUnavailable, statusCode: 503, validator: openRouter, model: .qwen37Plus)

        let miniMax = MiniMaxClient(region: .china, session: makeSession())
        await assertHTTPError(.invalidKey, statusCode: 401, validator: miniMax, model: .miniMaxM3)
        await assertHTTPError(
            .insufficientBalance, statusCode: 200,
            body: #"{"base_resp":{"status_code":1008,"status_msg":"insufficient balance"}}"#,
            validator: miniMax, model: .miniMaxM3)
        await assertHTTPError(
            .rateLimited, statusCode: 200,
            body: #"{"base_resp":{"status_code":1002,"status_msg":"rate limited"}}"#,
            validator: miniMax, model: .miniMaxM3)
        await assertHTTPError(
            .providerUnavailable, statusCode: 200,
            body: #"{"base_resp":{"status_code":1013,"status_msg":"internal error"}}"#,
            validator: miniMax, model: .miniMaxM3)
        await assertHTTPError(
            .invalidRequest, statusCode: 200,
            body: #"{"base_resp":{"status_code":2013,"status_msg":"invalid parameter"}}"#,
            validator: miniMax, model: .miniMaxM3)
        await assertHTTPError(
            .invalidRequest, statusCode: 200,
            body:
                #"{"id":"m3_1","model":"MiniMax-M3","choices":[{"message":{"content":""},"finish_reason":"content_filter"}],"base_resp":{"status_code":0}}"#,
            validator: miniMax, model: .miniMaxM3)

        AnalysisURLProtocolStub.stub(
            statusCode: 403,
            body: #"{"error":{"code":403,"message":"No endpoints match policy"}}"#
        )
        do {
            try await openRouter.validate(apiKey: "key", model: .qwen37Plus)
            XCTFail("Expected invalid request")
        } catch let error as ProviderConnectionError {
            guard case .invalidRequest(let details) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertEqual(details.provider, ProviderPlatform.openRouter.rawValue)
            XCTAssertEqual(details.httpStatus, 403)
            XCTAssertEqual(details.providerCode, "403")
            XCTAssertTrue(details.message.contains("required model, privacy"))
        } catch {
            XCTFail("Expected ProviderConnectionError, got \(error)")
        }

    }

    @MainActor
    private func assertInvalidResponse(
        from validator: any ProviderValidator,
        model: ProviderModel,
        body: String
    ) async {
        AnalysisURLProtocolStub.stub(statusCode: 200, body: body)
        await assertThrows(.invalidResponse) {
            try await validator.validate(apiKey: "key", model: model)
        }
    }

    @MainActor
    private func assertHTTPError(
        _ expected: ProviderErrorKind,
        statusCode: Int,
        body: String = #"{"error":{"message":"Failure"}}"#,
        validator: any ProviderValidator,
        model: ProviderModel
    ) async {
        AnalysisURLProtocolStub.stub(statusCode: statusCode, body: body)
        await assertThrows(expected) {
            try await validator.validate(apiKey: "key", model: model)
        }
    }

    @MainActor
    private func assertThrows(
        _ expected: ProviderErrorKind,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(ProviderErrorKind(error), expected)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private enum ProviderErrorKind: Equatable {
    case invalidKey
    case insufficientBalance
    case rateLimited
    case providerUnavailable
    case invalidRequest
    case invalidResponse
    case other

    init(_ error: Error) {
        guard let error = error as? ProviderConnectionError else {
            self = .other
            return
        }

        switch error {
        case .invalidKey:
            self = .invalidKey
        case .insufficientBalance:
            self = .insufficientBalance
        case .rateLimited:
            self = .rateLimited
        case .providerUnavailable:
            self = .providerUnavailable
        case .invalidRequest:
            self = .invalidRequest
        case .invalidResponse:
            self = .invalidResponse
        default:
            self = .other
        }
    }
}
