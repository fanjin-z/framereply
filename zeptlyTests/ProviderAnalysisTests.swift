import Foundation
import XCTest

@testable import zeptly

final class ProviderAnalysisTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testFiveContractsHaveExactClosedRootKeys() throws {
        XCTAssertEqual(ChatScreenshotPrompt.version, 1)
        XCTAssertEqual(SuggestedReplyPrompt.version, 1)

        let screenshot = ChatScreenshotPrompt.contract(for: makeRequest())
        let shared = ChatScreenshotPrompt.contract(
            for: ChatImportAnalysisRequest(transcriptItems: ["Alice: Hi"], candidates: []))
        let standard = SuggestedReplyPrompt.contract(for: .standard)
        let drafting = SuggestedReplyPrompt.contract(for: .drafting)
        let persona = SuggestedReplyPrompt.contract(for: .personaStyleLearning)

        try assertContract(
            screenshot,
            keys: [
                "extractionStatus", "conversationTitle", "conversationKind", "titleSource",
                "ownershipConvention", "messages", "matchedChatID", "matchConfidence"
            ], version: ChatScreenshotPrompt.version)
        try assertContract(
            shared,
            keys: [
                "extractionStatus", "conversationTitle", "conversationKind", "titleSource",
                "messages", "matchedChatID", "matchConfidence"
            ], version: ChatScreenshotPrompt.version)
        try assertContract(
            standard,
            keys: [
                "historySummary", "replies", "conversationStrategy", "strategyRationale",
                "memoryChanges", "personaObservationChanges"
            ], version: SuggestedReplyPrompt.version)
        try assertContract(
            drafting,
            keys: ["replies", "conversationStrategy", "strategyRationale"],
            version: SuggestedReplyPrompt.version)
        try assertContract(
            persona, keys: ["personaObservationChanges"],
            version: SuggestedReplyPrompt.version)

        let screenshotText = try schemaText(screenshot.schema)
        let sharedText = try schemaText(shared.schema)
        for removed in ["quotedReply", "participants", "sourceApp", "matchBasis"] {
            XCTAssertFalse(screenshotText.contains("\"\(removed)\""))
            XCTAssertFalse(sharedText.contains("\"\(removed)\""))
        }
        XCTAssertTrue(screenshotText.contains("outerAlignment"))
        XCTAssertFalse(sharedText.contains("outerAlignment"))
        XCTAssertFalse(sharedText.contains("ownershipConvention"))
    }

    func testTaskInputsContainOnlyDataUsedByTheirContract() {
        let standard = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .standard))
        XCTAssertTrue(standard.contains("chatMemories"))
        XCTAssertTrue(standard.contains("personaLearningMessages"))
        XCTAssertTrue(standard.contains("recentMessages"))
        for removed in ["chatName", "personaName", "certainty", "origin"] {
            XCTAssertFalse(standard.contains("\"\(removed)\""))
        }

        let drafting = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .drafting))
        XCTAssertTrue(drafting.contains("draftingInput"))
        XCTAssertTrue(drafting.contains("recentMessages"))
        XCTAssertFalse(drafting.contains("personaLearningMessages"))
        XCTAssertFalse(drafting.contains("summaryMode"))

        let persona = SuggestedReplyPrompt.input(
            for: makeReplyRequest(task: .personaStyleLearning))
        XCTAssertTrue(persona.contains("personaLearningMessages"))
        XCTAssertTrue(persona.contains("activeObservations"))
        XCTAssertFalse(persona.contains("recentMessages"))
        XCTAssertFalse(persona.contains("chatMemories"))
        XCTAssertFalse(persona.contains("draftingInput"))
    }

    @MainActor
    func testOpenAIUsesStrictTaskSpecificWireContractsAndReportsUsage() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validScreenshotAnalysisJSON()))
        ]

        _ = try await OpenAIClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .gpt56Sol)

        let screenshotBody = try jsonBody(
            try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        )
        XCTAssertEqual(screenshotBody["store"] as? Bool, false)
        XCTAssertEqual(
            screenshotBody["prompt_cache_key"] as? String,
            "screenshot_import-v1-gpt-5.6-sol")
        let screenshotFormat = try XCTUnwrap(
            (screenshotBody["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(screenshotFormat["type"] as? String, "json_schema")
        XCTAssertEqual(screenshotFormat["strict"] as? Bool, true)
        XCTAssertEqual(screenshotFormat["name"] as? String, "screenshot_import")
        let input = try XCTUnwrap(screenshotBody["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first { $0["type"] as? String == "input_image" })
        XCTAssertEqual(image["detail"] as? String, "high")
        XCTAssertTrue(
            try XCTUnwrap(image["image_url"] as? String).hasPrefix("data:image/png;base64,"))

        AnalysisURLProtocolStub.reset()
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validDraftingJSON(), includeUsage: true))
        ]

        let result = try await OpenAIClient(
            session: makeSession(), eventReporter: reporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .drafting), apiKey: "key", model: .gpt56Luna)

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertTrue(result.memoryChanges.isEmpty)
        let replyBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        let replyFormat = try XCTUnwrap(
            (replyBody["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(replyFormat["name"] as? String, "suggested_reply_drafting")
        XCTAssertEqual(
            replyBody["prompt_cache_key"] as? String,
            "suggested_reply_drafting-v1-gpt-5.6-luna")
        let schema = try XCTUnwrap(replyFormat["schema"] as? [String: Any])
        XCTAssertEqual(
            Set(try XCTUnwrap(schema["properties"] as? [String: Any]).keys),
            ["replies", "conversationStrategy", "strategyRationale"])
        XCTAssertTrue(
            reporter.events.contains { event in
                guard
                    case .providerResponse(
                        _, _, _, _, _, _, _, _, _, let input, let output, let cached) = event
                else { return false }
                return input == 120 && output == 30 && cached == 80
            })
    }

    @MainActor
    func testZAIRepairsInvalidObjectsButNotTruncation() async throws {
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: "{}")),
            (200, zaiResponse(content: validStandardRepliesJSON(), includeUsage: true))
        ]

        let result = try await ZAIClient(
            region: .international, session: makeSession(), eventReporter: reporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .standard), apiKey: "key", model: .glm47FlashX)

        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 2)
        XCTAssertEqual(providerAttempts(in: reporter.events), [1, 2])
        let first = try jsonBody(AnalysisURLProtocolStub.requests[0])
        XCTAssertEqual(
            (first["response_format"] as? [String: Any])?["type"] as? String,
            "json_object")
        let firstMessages = try XCTUnwrap(first["messages"] as? [[String: Any]])
        XCTAssertTrue(
            try XCTUnwrap(firstMessages.first?["content"] as? String).contains(
                "Return JSON matching this exact schema"))
        let second = try jsonBody(AnalysisURLProtocolStub.requests[1])
        let secondMessages = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(secondMessages.count, 4)
        XCTAssertEqual(secondMessages[2]["role"] as? String, "assistant")
        XCTAssertEqual(secondMessages[3]["role"] as? String, "user")

        AnalysisURLProtocolStub.reset()
        let truncationReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: "{}", finishReason: "length")),
            (200, zaiResponse(content: validStandardRepliesJSON()))
        ]

        await assertThrowsErrorAsync {
            _ = try await ZAIClient(
                region: .international,
                session: self.makeSession(),
                eventReporter: truncationReporter
            ).generateSuggestedReplies(
                self.makeReplyRequest(task: .standard), apiKey: "key", model: .glm47FlashX)
        }
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: truncationReporter.events), [1])
    }

    private func assertContract(
        _ contract: AIOutputContract,
        keys: Set<String>,
        version: Int
    ) throws {
        XCTAssertEqual(contract.version, version)
        XCTAssertEqual(contract.schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(contract.schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), keys)
        XCTAssertEqual(Set(try XCTUnwrap(contract.schema["required"] as? [String])), keys)
    }

    private func schemaText(_ schema: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private var screenshotData: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
    }

    private func makeRequest() -> ChatScreenshotAnalysisRequest {
        ChatScreenshotAnalysisRequest(imageData: screenshotData, candidates: [])
    }

    private func makeReplyRequest(task: SuggestedReplyTask) -> SuggestedReplyGenerationRequest {
        SuggestedReplyGenerationRequest(
            task: task,
            chatMemories: [
                ChatMemory(text: "Met at university", origin: .user, certainty: .userConfirmed)
            ],
            currentInteractionGoal: "Confirm dinner",
            persona: PersonaPromptContext(
                id: UUID(), name: "Warm", instructions: "Write warmly.",
                observations: [
                    PersonaObservation(
                        id: UUID(), text: "Uses short sentences.", origin: .user,
                        isUserProtected: true, status: .active,
                        createdAt: Date(), updatedAt: Date())
                ], protectedTombstones: []),
            personaLearningMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "user", senderName: nil, text: "Sure", timeLabel: "")
            ],
            existingHistorySummary: "Earlier context",
            summaryMode: .unchanged,
            olderMessagesToSummarize: [],
            recentMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "other_participant", senderName: "Sarah",
                    text: "Dinner at 7?", timeLabel: "6:00 PM")
            ],
            draftingInput: task == .drafting ? "Make it warmer" : nil,
            previousConversationStrategy: "Confirm the plan.",
            traceID: ImportTraceID())
    }

    private func validScreenshotAnalysisJSON() -> String {
        jsonString([
            "extractionStatus": "ok",
            "conversationTitle": "Sarah",
            "conversationKind": "direct",
            "titleSource": "header",
            "ownershipConvention": [
                "mode": "opposed_alignment", "screenshotOwnerAlignment": "right",
                "screenshotOwnerAuthorLabel": NSNull()
            ],
            "messages": [
                [
                    "sender": "other_participant", "senderName": "Sarah", "text": "Hello",
                    "timestampLabel": NSNull(), "outerAlignment": "left",
                    "outerAuthorLabel": NSNull(), "senderConfidence": 0.95,
                    "senderEvidence": "alignment_convention"
                ]
            ],
            "matchedChatID": NSNull(), "matchConfidence": 0.0
        ])
    }

    private func validStandardRepliesJSON() -> String {
        jsonString([
            "historySummary": NSNull(), "replies": ["First", "Second"],
            "conversationStrategy": "Answer directly and keep momentum.",
            "strategyRationale": "The latest message asks for a concrete confirmation.",
            "memoryChanges": [], "personaObservationChanges": []
        ])
    }

    private func validDraftingJSON() -> String {
        jsonString([
            "replies": ["First", "Second"],
            "conversationStrategy": "Answer directly and keep momentum.",
            "strategyRationale": "The one-use instruction asks for warmer wording."
        ])
    }

    private func openAIResponse(content: String, includeUsage: Bool = false) -> String {
        var object: [String: Any] = [
            "id": "resp_test", "status": "completed",
            "output": [
                [
                    "type": "message", "content": [["type": "output_text", "text": content]]
                ]
            ]
        ]
        if includeUsage {
            object["usage"] = [
                "input_tokens": 120, "output_tokens": 30,
                "input_tokens_details": ["cached_tokens": 80]
            ]
        }
        return jsonString(object)
    }

    private func zaiResponse(
        content: String?,
        finishReason: String = "stop",
        includeUsage: Bool = false
    ) -> String {
        var object: [String: Any] = [
            "choices": [
                [
                    "message": ["content": content.map { $0 as Any } ?? NSNull()],
                    "finish_reason": finishReason
                ]
            ]
        ]
        if includeUsage {
            object["usage"] = [
                "prompt_tokens": 100, "completion_tokens": 20,
                "prompt_tokens_details": ["cached_tokens": 60]
            ]
        }
        return jsonString(object)
    }

    private func jsonString(_ object: Any) -> String {
        String(
            data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            encoding: .utf8)!
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

    private func providerAttempts(in events: [ImportEvent]) -> [Int] {
        events.compactMap { event in
            guard case .providerAttempt(_, _, _, let attempt, _) = event else { return nil }
            return attempt
        }
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
            headerFields: ["Content-Type": "application/json", "x-request-id": "req-test"]
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

private func assertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
