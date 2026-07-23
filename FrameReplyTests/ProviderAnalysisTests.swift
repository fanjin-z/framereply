import Foundation
import XCTest

@testable import FrameReply

final class ProviderAnalysisTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testFiveContractsHaveExactClosedRootKeys() throws {
        XCTAssertEqual(ChatScreenshotPrompt.version, 1)
        XCTAssertEqual(SuggestedReplyPrompt.version, 3)

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

        XCTAssertEqual(standard.name, "suggested_reply")
        let summaryProperties = try XCTUnwrap(
            standard.schema["properties"] as? [String: Any])
        let summarySchema = try XCTUnwrap(
            summaryProperties["historySummary"] as? [String: Any])
        XCTAssertEqual(summarySchema["type"] as? [String], ["string", "null"])
        XCTAssertTrue(standard.instructions.contains("olderMessagesToSummarize is empty"))
        XCTAssertTrue(standard.instructions.contains("merge existingHistorySummary"))
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
            "suggested_reply_drafting-v3-gpt-5.6-luna-en")
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

    func testSuggestedReplyDecoderRecoversSecondaryFieldsAndPreservesCoreReplies() throws {
        let content = jsonString([
            "historySummary": 42,
            "replies": [" First ", NSNull(), "first", " Second ", "Third"],
            "conversationStrategy": NSNull(),
            "memoryChanges": "invalid",
            "extra": true
        ])
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: "Result:\n\(content)", finishReason: "stop", task: .standard)

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.replies, ["First", "Second"])
        XCTAssertNil(decoded.value.historySummary)
        XCTAssertEqual(decoded.value.conversationStrategy, "")
        XCTAssertEqual(decoded.value.strategyRationale, "")
        XCTAssertTrue(decoded.value.memoryChanges.isEmpty)
        XCTAssertTrue(decoded.value.personaObservationChanges.isEmpty)
        XCTAssertFalse(decoded.value.personaObservationChangesAvailable)
    }

    func testSuggestedReplyDecoderHandlesSummaryAndJSONWrappersConservatively() throws {
        let valid = validStandardRepliesJSON(historySummary: " Merged summary ")
        XCTAssertEqual(
            try SuggestedReplyResultDecoder.decode(
                content: valid, finishReason: "stop", task: .standard
            ).historySummary,
            "Merged summary")
        XCTAssertTrue(
            try SuggestedReplyResultDecoder.decodeResult(
                content: "```json\n\(valid)\n```", finishReason: "stop", task: .standard
            ).recovered)

        for invalidSummary: Any in [
            NSNull(), 42, "", String(repeating: "x", count: 2_001)
        ] {
            XCTAssertNil(
                try SuggestedReplyResultDecoder.decode(
                    content: validStandardRepliesJSON(historySummary: invalidSummary),
                    finishReason: "stop", task: .standard
                ).historySummary)
        }
        XCTAssertNil(
            try SuggestedReplyResultDecoder.decode(
                content: validStandardRepliesJSON(), finishReason: "stop", task: .standard
            ).historySummary)
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: jsonString(["replies": ["same", " same "]]),
                finishReason: "stop", task: .standard))
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: "\(valid)\n\(valid)", finishReason: "stop", task: .standard))
    }

    func testSuggestedReplyDecoderRetainsOnlyValidLearningChanges() throws {
        let memoryEvidence = UUID()
        let personaEvidence = [UUID(), UUID()]
        let content = jsonString([
            "historySummary": NSNull(),
            "replies": ["First", "Second"],
            "conversationStrategy": "Continue",
            "strategyRationale": "The latest message supports a direct answer.",
            "memoryChanges": [
                [
                    "action": "add", "targetMemoryID": NSNull(), "text": "Likes tea",
                    "evidenceMessageIDs": [memoryEvidence.uuidString]
                ],
                ["action": "add", "targetMemoryID": NSNull(), "text": 42]
            ],
            "personaObservationChanges": [
                [
                    "action": "add", "targetObservationID": NSNull(),
                    "text": "Uses short sentences",
                    "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                ],
                ["action": "invented"]
            ]
        ])

        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: content, finishReason: "stop", task: .standard)
        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.memoryChanges.count, 1)
        XCTAssertEqual(decoded.value.personaObservationChanges.count, 1)
        XCTAssertTrue(decoded.value.personaObservationChangesAvailable)

        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: "{}", finishReason: "stop", task: .personaStyleLearning))
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: #"{"personaObservationChanges":[{"action":"invented"}]}"#,
                finishReason: "stop",
                task: .personaStyleLearning))
    }

    @MainActor
    func testOpenAIUsesOneStandardContractAndOneRequestForRecoveredOrFatalOutput() async throws {
        let recoveredJSON = jsonString([
            "replies": [" First ", "Second"],
            "historySummary": NSNull()
        ])
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: "```json\n\(recoveredJSON)\n```"))
        ]
        let result = try await OpenAIClient(
            session: makeSession(), eventReporter: reporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .standard, hasOlderMessages: true),
            apiKey: "key",
            model: .gpt56Terra
        )
        XCTAssertEqual(result.replies, ["First", "Second"])
        XCTAssertNil(result.historySummary)
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: reporter.events), [1])
        let body = try jsonBody(AnalysisURLProtocolStub.requests[0])
        XCTAssertEqual(
            body["prompt_cache_key"] as? String,
            "suggested_reply-v3-gpt-5.6-terra-en")
        XCTAssertEqual(
            ((body["text"] as? [String: Any])?["format"] as? [String: Any])?["name"]
                as? String,
            "suggested_reply")
        XCTAssertTrue(hasValidationCategory("recovered", in: reporter.events))

        AnalysisURLProtocolStub.reset()
        let fatalReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: "{}")),
            (200, openAIResponse(content: validStandardRepliesJSON()))
        ]
        await assertThrowsErrorAsync(
            {
                _ = try await OpenAIClient(
                    session: self.makeSession(), eventReporter: fatalReporter
                ).generateSuggestedReplies(
                    self.makeReplyRequest(task: .standard),
                    apiKey: "key",
                    model: .gpt56Terra
                )
            },
            errorHandler: {
                self.assertStructuredOutputError($0, provider: "openai", codingPath: "root")
            })
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
        XCTAssertTrue(hasValidationCategory("fatal", in: fatalReporter.events))
    }

    @MainActor
    func testOpenAIImportUsesOneRequestForRecoveredAndFatalOutput() async throws {
        let recoveredReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: #"{"messages":[{"text":"Hello"}]}"#))
        ]
        let recovered = try await OpenAIClient(
            session: makeSession(), eventReporter: recoveredReporter
        ).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .gpt56Sol)
        XCTAssertEqual(recovered.messages.first?.text, "Hello")
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: recoveredReporter.events), [1])
        XCTAssertTrue(hasValidationCategory("recovered", in: recoveredReporter.events))

        AnalysisURLProtocolStub.reset()
        let fatalReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: #"{"messages":[{"text":42}]}"#)),
            (200, openAIResponse(content: validScreenshotAnalysisJSON()))
        ]
        await assertThrowsErrorAsync(
            {
                _ = try await OpenAIClient(
                    session: self.makeSession(), eventReporter: fatalReporter
                ).analyzeChatScreenshot(
                    self.makeRequest(), apiKey: "key", model: .gpt56Sol)
            },
            errorHandler: {
                self.assertStructuredOutputError(
                    $0, provider: "openai", codingPath: "messages[0].text")
            })
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
    }

    @MainActor
    func testBothZAIRegionsUseOneRequestForRecoveredAndFatalReplies() async throws {
        for (region, provider) in [
            (ZAIClient.Region.international, "zaiInternational"),
            (.china, "zhipuChina")
        ] {
            AnalysisURLProtocolStub.reset()
            let recoveredReporter = SpyImportEventReporter()
            AnalysisURLProtocolStub.responses = [
                (200, zaiResponse(content: #"{"replies":["First","Second"]}"#))
            ]
            let recovered = try await ZAIClient(
                region: region,
                session: makeSession(),
                eventReporter: recoveredReporter
            ).generateSuggestedReplies(
                makeReplyRequest(task: .standard),
                apiKey: "key",
                model: .glm47FlashX
            )
            XCTAssertEqual(recovered.replies, ["First", "Second"])
            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            XCTAssertEqual(providerAttempts(in: recoveredReporter.events), [1])
            XCTAssertTrue(hasValidationCategory("recovered", in: recoveredReporter.events))

            let first = try jsonBody(AnalysisURLProtocolStub.requests[0])
            XCTAssertEqual(
                (first["response_format"] as? [String: Any])?["type"] as? String,
                "json_object")
            let firstMessages = try XCTUnwrap(first["messages"] as? [[String: Any]])
            XCTAssertTrue(
                try XCTUnwrap(firstMessages.first?["content"] as? String).contains(
                    "Return JSON matching this exact schema"))
            XCTAssertEqual(firstMessages.count, 2)

            AnalysisURLProtocolStub.reset()
            let fatalReporter = SpyImportEventReporter()
            AnalysisURLProtocolStub.responses = [
                (200, zaiResponse(content: "{}")),
                (200, zaiResponse(content: validStandardRepliesJSON(), includeUsage: true))
            ]
            await assertThrowsErrorAsync(
                {
                    _ = try await ZAIClient(
                        region: region,
                        session: self.makeSession(),
                        eventReporter: fatalReporter
                    ).generateSuggestedReplies(
                        self.makeReplyRequest(task: .standard),
                        apiKey: "key",
                        model: .glm47FlashX
                    )
                },
                errorHandler: {
                    self.assertStructuredOutputError(
                        $0, provider: provider, codingPath: "root")
                })
            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
        }
    }

    @MainActor
    func testZAIScreenshotAnalysisUsesOneRequestForRecoveredAndFatalOutput() async throws {
        let recoveredReporter = SpyImportEventReporter()
        let minimal = #"{"messages":[{"text":"Hello"}]}"#
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: "Result:\n\(minimal)"))
        ]
        let recovered = try await ZAIClient(
            region: .international,
            session: makeSession(),
            eventReporter: recoveredReporter
        ).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .glm46VFlashX)
        XCTAssertEqual(recovered.messages.first?.text, "Hello")
        XCTAssertEqual(recovered.messages.first?.sender, .unknown)
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: recoveredReporter.events), [1])
        XCTAssertTrue(hasValidationCategory("recovered", in: recoveredReporter.events))

        AnalysisURLProtocolStub.reset()
        let fatalReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: #"{"messages":[{"text":42}]}"#)),
            (200, zaiResponse(content: validScreenshotAnalysisJSON()))
        ]
        await assertThrowsErrorAsync(
            {
                _ = try await ZAIClient(
                    region: .international,
                    session: self.makeSession(),
                    eventReporter: fatalReporter
                ).analyzeChatScreenshot(
                    self.makeRequest(), apiKey: "key", model: .glm46VFlashX)
            },
            errorHandler: {
                self.assertStructuredOutputError(
                    $0, provider: "zaiInternational", codingPath: "messages[0].text")
            })
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
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

    private func makeReplyRequest(
        task: SuggestedReplyTask,
        hasOlderMessages: Bool = false,
        existingHistorySummary: String = "Earlier context"
    ) -> SuggestedReplyGenerationRequest {
        let olderMessages =
            hasOlderMessages
            ? [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "other_participant", senderName: "Sarah",
                    text: "We chose the Italian restaurant.", timeLabel: "Yesterday")
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
                        createdAt: Date(), updatedAt: Date())
                ], protectedTombstones: []),
            personaLearningMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "user", senderName: nil, text: "Sure", timeLabel: "")
            ],
            existingHistorySummary: existingHistorySummary,
            olderMessagesToSummarize: olderMessages,
            recentMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "other_participant", senderName: "Sarah",
                    text: "Dinner at 7?", timeLabel: "6:00 PM")
            ],
            draftingInput: task == .drafting ? "Make it warmer" : nil,
            previousConversationStrategy: "Confirm the plan.",
            presentationLanguageIdentifier: "en",
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

    private func validStandardRepliesJSON(historySummary: Any? = nil) -> String {
        var object: [String: Any] = [
            "replies": ["First", "Second"],
            "conversationStrategy": "Answer directly and keep momentum.",
            "strategyRationale": "The latest message asks for a concrete confirmation.",
            "memoryChanges": [], "personaObservationChanges": []
        ]
        if let historySummary {
            object["historySummary"] = historySummary
        }
        return jsonString(object)
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

    private func hasValidationCategory(_ category: String, in events: [ImportEvent]) -> Bool {
        events.contains { event in
            guard case .contractValidation(_, _, _, _, _, let value) = event else {
                return false
            }
            return value == category
        }
    }

    private func assertStructuredOutputError(
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
