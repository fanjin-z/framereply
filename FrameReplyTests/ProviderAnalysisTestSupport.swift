import Foundation
import XCTest

@testable import FrameReply

class ProviderAnalysisTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func schemaText(_ schema: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    var screenshotData: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
    }

    func makeRequest() -> ChatScreenshotAnalysisRequest {
        ChatScreenshotAnalysisRequest(imageData: screenshotData, candidates: [])
    }

    func makeReplyRequest(
        task: SuggestedReplyTask,
        hasOlderMessages: Bool = false,
        existingHistorySummary: String = "Earlier context",
        appLanguage: String = "en",
        recentMessageText: String = "Dinner at 7?",
        personaLearningText: String = "Sure"
    ) -> SuggestedReplyGenerationRequest {
        let olderMessages =
            hasOlderMessages
            ? [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "other_participant", senderName: "Sarah",
                    text: "We chose the Italian restaurant.", timeLabel: "Yesterday"
                )
            ] : []
        return SuggestedReplyGenerationRequest(
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
                        createdAt: Date(), updatedAt: Date()
                    )
                ],
                protectedTombstones: []
            ),
            personaLearningEnabled: task == .standard,
            personalInfo: PersonalInfoPromptContext(
                facts: [PersonalInfoFact(text: "Prefers window seats", origin: .user)]
            ),
            personalInfoLearningEnabled: task == .standard,
            existingHistorySummary: existingHistorySummary,
            olderMessagesToSummarize: olderMessages,
            recentMessages: task == .personaStyleLearning
                ? [
                    SuggestedReplyPromptMessage(
                        id: UUID(), sender: "user", senderName: nil,
                        text: personaLearningText, timeLabel: ""
                    )
                ]
                : [
                    SuggestedReplyPromptMessage(
                        id: UUID(), sender: "user", senderName: nil,
                        text: personaLearningText, timeLabel: ""
                    ),
                    SuggestedReplyPromptMessage(
                        id: UUID(), sender: "other_participant", senderName: "Sarah",
                        text: recentMessageText, timeLabel: "6:00 PM"
                    )
                ],
            draftingInput: task == .drafting ? "Make it warmer" : nil,
            previousConversationStrategy: "Confirm the plan.",
            appLanguage: appLanguage,
            traceID: ImportTraceID()
        )
    }

    func validScreenshotAnalysisJSON() -> String {
        jsonString([
            "conversationTitle": "Sarah",
            "conversationKindEvidence": "no_group_evidence",
            "titleSource": "header",
            "userIdentification": [
                "mode": "opposed_alignment", "userAlignment": "right",
                "userAuthorLabel": NSNull()
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

    func validStandardRepliesJSON(historySummary: Any? = nil) -> String {
        var object: [String: Any] = [
            "replies": ["First", "Second"],
            "conversationStrategy": "Answer directly and keep momentum.",
            "strategyRationale": "The latest message asks for a concrete confirmation.",
            "memoryChanges": [], "personaObservationChanges": [],
            "personalInfoChanges": []
        ]
        if let historySummary {
            object["historySummary"] = historySummary
        }
        return jsonString(object)
    }

    func validDraftingJSON() -> String {
        jsonString([
            "replies": ["First", "Second"],
            "conversationStrategy": "Answer directly and keep momentum.",
            "strategyRationale": "The one-use instruction asks for warmer wording."
        ])
    }

    func openAIResponse(content: String, includeUsage: Bool = false) -> String {
        var object: [String: Any] = [
            "id": "resp_test", "status": "completed",
            "output": [
                ["type": "message", "content": [["type": "output_text", "text": content]]]
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

    func openRouterResponse(content: String) -> String {
        jsonString([
            "id": "gen_test",
            "model": "qwen/qwen3.7-plus",
            "choices": [["message": ["content": content], "finish_reason": "stop"]]
        ])
    }

    func miniMaxResponse(
        content: String?,
        finishReason: String = "stop",
        includeUsage: Bool = false
    ) -> String {
        var object: [String: Any] = [
            "id": "m3_test",
            "model": "MiniMax-M3",
            "choices": [
                [
                    "message": ["content": content.map { $0 as Any } ?? NSNull()],
                    "finish_reason": finishReason
                ]
            ],
            "base_resp": ["status_code": 0, "status_msg": "success"]
        ]
        if includeUsage {
            object["usage"] = [
                "prompt_tokens": 100, "completion_tokens": 20,
                "prompt_tokens_details": ["cached_tokens": 60]
            ]
        }
        return jsonString(object)
    }

    func jsonString(_ object: Any) -> String {
        String(
            data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            encoding: .utf8
        )!
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func providerAttempts(in events: [ImportEvent]) -> [Int] {
        events.compactMap { event in
            guard case .providerAttempt(_, _, _, let attempt, _) = event else { return nil }
            return attempt
        }
    }

    func hasValidationCategory(_ category: String, in events: [ImportEvent]) -> Bool {
        events.contains { event in
            guard case .contractValidation(_, _, _, _, _, let value) = event else {
                return false
            }
            return value == category
        }
    }

    func assertStructuredOutputError(
        _ error: Error,
        provider: String,
        codingPath: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let providerError = error as? ProviderConnectionError,
            case .structuredOutput(let detail) = providerError
        else {
            XCTFail("Expected structured-output error, got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(detail.provider, provider, file: file, line: line)
        XCTAssertEqual(detail.failure.kind, .schemaMismatch, file: file, line: line)
        XCTAssertEqual(detail.failure.codingPath, codingPath, file: file, line: line)
    }
}

final class SpyImportEventReporter: ImportEventReporting, @unchecked Sendable {
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

final class AnalysisURLProtocolStub: URLProtocol {
    static var requests: [URLRequest] = []
    static var responses: [(Int, String)] = []

    static func reset() {
        requests = []
        responses = []
    }

    static func stub(statusCode: Int, body: String) {
        responses = [(statusCode, body)]
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

func assertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
