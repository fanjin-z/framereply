import Foundation
import XCTest

@testable import FrameReply

final class ProviderValidatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    @MainActor
    func testProvidersUseOneSelectedModelProbe() async throws {
        URLProtocolStub.stub(
            statusCode: 200,
            body: #"{"choices":[{"index":0,"message":{"content":"OK"},"finish_reason":"stop"}]}"#
        )

        try await ZAIClient(region: .international, session: makeSession()).validate(
            apiKey: "zai-key",
            model: .glm46VFlashX
        )

        XCTAssertEqual(URLProtocolStub.requests.count, 1)
        let zaiRequest = try XCTUnwrap(URLProtocolStub.requests.first)
        XCTAssertEqual(zaiRequest.url?.path, "/api/paas/v4/chat/completions")
        XCTAssertFalse(zaiRequest.url?.path.contains("balance") == true)
        XCTAssertEqual(zaiRequest.value(forHTTPHeaderField: "Authorization"), "Bearer zai-key")

        let zaiBody = try jsonBody(zaiRequest)
        XCTAssertEqual(zaiBody["model"] as? String, "glm-4.6v-flashx")
        XCTAssertEqual(zaiBody["max_tokens"] as? Int, 64)
        XCTAssertEqual((zaiBody["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual(zaiBody["do_sample"] as? Bool, false)
        let messages = try XCTUnwrap(zaiBody["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "Reply exactly: OK.")

        URLProtocolStub.reset()
        URLProtocolStub.stub(
            statusCode: 200,
            body:
                #"{"id":"resp_1","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
        )

        try await OpenAIClient(session: makeSession()).validate(
            apiKey: "open-key",
            model: .gpt56Luna
        )

        XCTAssertEqual(URLProtocolStub.requests.count, 1)
        let openAIRequest = try XCTUnwrap(URLProtocolStub.requests.first)
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
    }

    @MainActor
    func testProvidersRejectMalformedResponses() async {
        await assertInvalidResponse(
            from: ZAIClient(region: .china, session: makeSession()),
            model: .glm46VFlash,
            body: #"{"choices":[]}"#
        )
        await assertInvalidResponse(
            from: OpenAIClient(session: makeSession()),
            model: .gpt56Luna,
            body:
                #"{"id":"resp_1","status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
        )
    }

    @MainActor
    func testProvidersMapHTTPFailures() async {
        let validator = ZAIClient(region: .international, session: makeSession())
        await assertHTTPError(
            .invalidKey, statusCode: 401, validator: validator, model: .glm46VFlashX)
        await assertHTTPError(
            .insufficientBalance, statusCode: 402, validator: validator, model: .glm46VFlashX)
        await assertHTTPError(
            .rateLimited, statusCode: 429, validator: validator, model: .glm46VFlashX)
        await assertHTTPError(
            .providerUnavailable, statusCode: 503, validator: validator, model: .glm46VFlashX)
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

        URLProtocolStub.stub(
            statusCode: 400,
            body:
                #"{"error":{"code":1214,"message":"Invalid API parameter, please check the documentation."}}"#
        )

        do {
            try await ZAIClient(region: .china, session: makeSession()).validate(
                apiKey: "key",
                model: .glm46V
            )
            XCTFail("Expected invalid request")
        } catch let error as ProviderConnectionError {
            guard case .invalidRequest(let details) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertEqual(details.provider, ProviderPlatform.zhipuChina.rawValue)
            XCTAssertEqual(details.httpStatus, 400)
            XCTAssertEqual(details.providerCode, "1214")
            XCTAssertEqual(error.shortcutErrorCode, "provider_invalid_request")
            XCTAssertEqual(
                error.localizedDescription, "智谱 (国内) rejected an API parameter."
            )
            XCTAssertFalse(String(describing: details).contains("key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    private func assertInvalidResponse(
        from validator: any ProviderValidator,
        model: ProviderModel,
        body: String
    ) async {
        URLProtocolStub.stub(statusCode: 200, body: body)
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
        URLProtocolStub.stub(statusCode: statusCode, body: body)
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
        configuration.protocolClasses = [URLProtocolStub.self]
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
        case .invalidResponse:
            self = .invalidResponse
        default:
            self = .other
        }
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requests: [URLRequest] = []
    private static var statusCode = 200
    private static var responseBody = Data()

    static func reset() {
        requests = []
        statusCode = 200
        responseBody = Data()
    }

    static func stub(statusCode: Int, body: String) {
        self.statusCode = statusCode
        responseBody = Data(body.utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var recordedRequest = request
        if recordedRequest.httpBody == nil, let stream = request.httpBodyStream {
            recordedRequest.httpBody = Self.readData(from: stream)
        }
        Self.requests.append(recordedRequest)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readData(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
