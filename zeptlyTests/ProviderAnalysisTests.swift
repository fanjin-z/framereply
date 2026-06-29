import Foundation
import XCTest
@testable import zeptly

final class ProviderAnalysisTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testPromptUsesAppAgnosticHierarchyAndTrimmedContract() throws {
        let instructions = ChatScreenshotPrompt.instructions

        XCTAssertTrue(instructions.contains("top-level message container"))
        XCTAssertTrue(instructions.contains("App identity, language, pronouns"))
        XCTAssertTrue(instructions.contains("Authored blockquote"))
        XCTAssertTrue(instructions.contains("quotedReply"))
        XCTAssertTrue(instructions.contains("the single screenshot-wide rule mapping"))
        XCTAssertTrue(instructions.contains("right as a weak default only"))
        XCTAssertTrue(instructions.contains("Mandatory consistency"))
        XCTAssertTrue(instructions.contains(#""contact" is the one other participant in a direct chat"#))
        XCTAssertTrue(instructions.contains(#""other" is a group non-owner identified by visible outerAuthorLabel"#))
        for field in [
            "conversationTitle", "conversationKind", "titleSource", "avatarBounds", "messages",
            "matchedChatID", "matchConfidence", "ownershipConvention", "screenshotOwnerAlignment",
            "screenshotOwnerAuthorLabel", "outerAlignment", "outerAuthorLabel",
            "hasOutboundStatusIndicator", "senderName", "senderConfidence", "senderEvidence"
        ] {
            XCTAssertTrue(instructions.contains(field), "Missing prompt definition for \(field)")
        }
        for appName in ["WhatsApp", "Instagram", "WeChat", "Telegram", "Signal", "LINE", "Discord"] {
            XCTAssertFalse(instructions.contains(appName))
        }

        let schemaData = try JSONSerialization.data(withJSONObject: ChatScreenshotPrompt.jsonSchema)
        let schema = try XCTUnwrap(String(data: schemaData, encoding: .utf8))
        let canonical = ChatScreenshotPrompt.canonicalJSONExample
        for removedKey in ["participants", "sourceApp", "matchBasis"] {
            XCTAssertFalse(schema.contains(#""\#(removedKey)""#))
            XCTAssertFalse(canonical.contains(#""\#(removedKey)""#))
        }
        let rootProperties = try XCTUnwrap(
            ChatScreenshotPrompt.jsonSchema["properties"] as? [String: Any]
        )
        let ownershipSchema = try XCTUnwrap(
            rootProperties["ownershipConvention"] as? [String: Any]
        )
        let ownershipProperties = try XCTUnwrap(
            ownershipSchema["properties"] as? [String: Any]
        )
        XCTAssertNil(ownershipProperties["evidence"])
        XCTAssertNil(ownershipProperties["currentUserAlignment"])
        XCTAssertNil(ownershipProperties["currentUserAuthorLabel"])
        XCTAssertNotNil(ownershipProperties["screenshotOwnerAlignment"])
        XCTAssertNotNil(ownershipProperties["screenshotOwnerAuthorLabel"])
        XCTAssertFalse(
            try XCTUnwrap(ownershipSchema["required"] as? [String]).contains("evidence")
        )

        let exampleData = try XCTUnwrap(canonical.data(using: .utf8))
        let example = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exampleData) as? [String: Any]
        )
        let messages = try XCTUnwrap(example["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["sender"] as? String, "user")
        XCTAssertEqual(messages[0]["outerAlignment"] as? String, "right")
        XCTAssertTrue(messages[0]["outerAuthorLabel"] is NSNull)
        XCTAssertEqual(messages[0]["hasOutboundStatusIndicator"] as? Bool, true)
        XCTAssertEqual(messages[0]["senderEvidence"] as? String, "outbound_status")
        XCTAssertEqual(messages[1]["sender"] as? String, "contact")
        XCTAssertEqual(messages[1]["outerAlignment"] as? String, "left")
        XCTAssertNotNil(messages[1]["quotedReply"] as? [String: Any])
    }

    @MainActor
    func testOpenAISendsBase64ImageWithStructuredOutputAndNoOCRTranscript() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validAnalysisJSON(matchedChatID: "sarah-jenkins")))
        ]

        _ = try await OpenAIClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(),
            apiKey: "open-key",
            model: .gpt54Mini
        )

        let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/responses")
        let body = try jsonBody(request)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(((body["text"] as? [String: Any])?["format"] as? [String: Any])?["type"] as? String, "json_schema")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first { $0["type"] as? String == "input_image" })
        XCTAssertEqual(image["detail"] as? String, "high")
        XCTAssertTrue(try XCTUnwrap(image["image_url"] as? String).hasPrefix("data:image/png;base64,"))
        let prompt = try XCTUnwrap(content.first { $0["type"] as? String == "input_text" }?["text"] as? String)
        XCTAssertFalse(prompt.contains("OCR observations"))
        XCTAssertTrue(try XCTUnwrap(body["instructions"] as? String).contains("Literal visual observations"))
    }

    @MainActor
    func testOpenAIFullModelsUseOriginalImageDetail() async throws {
        for model in [ProviderModel.gpt54, .gpt55] {
            AnalysisURLProtocolStub.responses = [(200, openAIResponse(content: validAnalysisJSON(matchedChatID: nil)))]
            _ = try await OpenAIClient(session: makeSession()).analyzeChatScreenshot(
                makeRequest(), apiKey: "open-key", model: model
            )
            let body = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.last))
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first { $0["type"] as? String == "input_image" }?["detail"] as? String, "original")
        }
    }

    @MainActor
    func testBothZAIRegionsUseTheirOwnEndpointAndMultimodalShape() async throws {
        let cases: [(ZAIClient.Region, String)] = [
            (.international, "api.z.ai"),
            (.china, "open.bigmodel.cn")
        ]

        for (region, host) in cases {
            AnalysisURLProtocolStub.responses = [(200, zaiResponse(content: validAnalysisJSON(matchedChatID: nil)))]
            _ = try await ZAIClient(region: region, session: makeSession()).analyzeChatScreenshot(
                makeRequest(), apiKey: "regional-key", model: .glm46VFlashX
            )

            let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.last)
            XCTAssertEqual(request.url?.host, host)
            XCTAssertEqual(request.url?.path, "/api/paas/v4/chat/completions")
            let body = try jsonBody(request)
            XCTAssertEqual(body["model"] as? String, "glm-4.6v-flashx")
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            XCTAssertEqual(body["do_sample"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertTrue(try XCTUnwrap(messages.first?["content"] as? String).contains("Literal visual observations"))
            let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            let image = try XCTUnwrap(userContent.first { $0["type"] as? String == "image_url" })
            let imageURL = try XCTUnwrap((image["image_url"] as? [String: Any])?["url"] as? String)
            XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
        }
    }

    @MainActor
    func testZAIRetriesOneMalformedResponseWithRepairPrompt() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: "{}")),
            (200, zaiResponse(content: validAnalysisJSON(matchedChatID: nil)))
        ]

        _ = try await ZAIClient(region: .international, session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .glm46VFlash
        )

        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 2)
        let body = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.last))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let prompt = try XCTUnwrap(userContent.first { $0["type"] as? String == "text" }?["text"] as? String)
        XCTAssertTrue(prompt.contains("schema_mismatch"))
        XCTAssertTrue(prompt.contains("Canonical JSON example"))
    }

    @MainActor
    func testDiagnosticsDoNotContainImageKeyOrChatContent() async throws {
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [(200, zaiResponse(content: validAnalysisJSON(matchedChatID: nil)))]

        _ = try await ZAIClient(
            region: .international,
            session: makeSession(),
            eventReporter: reporter
        ).analyzeChatScreenshot(makeRequest(), apiKey: "super-secret-key", model: .glm46V)

        let description = String(describing: reporter.events)
        XCTAssertTrue(description.contains("providerAttempt"))
        XCTAssertTrue(description.contains("providerResponse"))
        XCTAssertFalse(description.contains("super-secret-key"))
        XCTAssertFalse(description.contains("Can we meet tomorrow?"))
        XCTAssertFalse(description.contains(screenshotData.base64EncodedString()))
    }

    private var screenshotData: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    }

    private func makeRequest() -> ChatScreenshotAnalysisRequest {
        ChatScreenshotAnalysisRequest(
            imageData: screenshotData,
            candidates: [
                ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
            ]
        )
    }

    private func validAnalysisJSON(matchedChatID: String?) -> String {
        let object: [String: Any] = [
            "conversationTitle": "Sarah Jenkins",
            "conversationKind": "direct",
            "titleSource": "header",
            "avatarBounds": NSNull(),
            "ownershipConvention": [
                "mode": "opposed_alignment",
                "screenshotOwnerAlignment": "right",
                "screenshotOwnerAuthorLabel": NSNull()
            ],
            "messages": [[
                "sender": "contact",
                "senderName": "Sarah Jenkins",
                "text": "Can we meet tomorrow?",
                "timestampLabel": "10:42 AM",
                "outerAlignment": "left",
                "outerAuthorLabel": NSNull(),
                "hasOutboundStatusIndicator": false,
                "senderConfidence": 0.95,
                "senderEvidence": "alignment_convention",
                "quotedReply": NSNull()
            ]],
            "matchedChatID": matchedChatID.map { $0 as Any } ?? NSNull(),
            "matchConfidence": matchedChatID == nil ? 0.0 : 0.96
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func openAIResponse(content: String) -> String {
        let object: [String: Any] = [
            "id": "resp_analysis",
            "status": "completed",
            "output": [["type": "message", "content": [["type": "output_text", "text": content]]]]
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func zaiResponse(content: String?, finishReason: String = "stop") -> String {
        let object: [String: Any] = [
            "choices": [[
                "message": ["content": content.map { $0 as Any } ?? NSNull()],
                "finish_reason": finishReason
            ]]
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
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

private final class SpyImportEventReporter: ImportEventReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImportEvent] = []

    var events: [ImportEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: ImportEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private final class AnalysisURLProtocolStub: URLProtocol {
    static var requests: [URLRequest] = []
    static var responses: [(Int, String)] = []

    static func reset() {
        requests = []
        responses = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recordedRequest = request
        if recordedRequest.httpBody == nil, let stream = request.httpBodyStream {
            recordedRequest.httpBody = Self.readData(from: stream)
        }
        Self.requests.append(recordedRequest)
        let stub = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.0, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.1.utf8))
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
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
