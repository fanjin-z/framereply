import Foundation
import XCTest

@testable import zeptly

final class ProviderAnalysisTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testScreenshotPromptSchemaAndExampleContract() throws {
        let schemaData = try JSONSerialization.data(withJSONObject: ChatScreenshotPrompt.jsonSchema)
        let schema = try XCTUnwrap(String(data: schemaData, encoding: .utf8))
        let canonical = ChatScreenshotPrompt.canonicalJSONExample
        for removedKey in ["participants", "sourceApp", "matchBasis", "hasOutboundStatusIndicator"]
        {
            XCTAssertFalse(schema.contains(#""\#(removedKey)""#))
            XCTAssertFalse(canonical.contains(#""\#(removedKey)""#))
        }
        XCTAssertFalse(schema.contains("outbound_status"))
        XCTAssertFalse(canonical.contains("outbound_status"))
        let rootProperties = try XCTUnwrap(
            ChatScreenshotPrompt.jsonSchema["properties"] as? [String: Any]
        )
        XCTAssertNotNil(rootProperties["conversationTitle"])
        XCTAssertNotNil(rootProperties["messages"])
        XCTAssertNotNil(rootProperties["ownershipConvention"])
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
        XCTAssertNil(messages[0]["hasOutboundStatusIndicator"])
        XCTAssertEqual(messages[0]["senderEvidence"] as? String, "message_status_indicator")
        XCTAssertEqual(messages[1]["sender"] as? String, "contact")
        XCTAssertEqual(messages[1]["outerAlignment"] as? String, "left")
        XCTAssertNotNil(messages[1]["quotedReply"] as? [String: Any])

        let multiImagePrompt = ChatScreenshotPrompt.input(
            for: ChatScreenshotAnalysisRequest(
                imageDataList: [screenshotData, secondScreenshotData],
                candidates: []
            )
        )
        XCTAssertTrue(multiImagePrompt.contains("same chat"))
        XCTAssertTrue(multiImagePrompt.contains("unordered"))
        XCTAssertTrue(multiImagePrompt.contains("overlap"))
        XCTAssertTrue(multiImagePrompt.contains("deduplicated transcript"))
    }

    func testSuggestedReplyPromptIncludesAllGroundingAndRequiresTwoDistinctReplies() throws {
        let prompt = SuggestedReplyPrompt.input(for: makeReplyRequest())
        XCTAssertFalse(prompt.contains(SuggestedReplyPrompt.canonicalJSONExample))
        XCTAssertEqual(
            SuggestedReplyPrompt.instructions.components(
                separatedBy: SuggestedReplyPrompt.canonicalJSONExample
            ).count
                - 1,
            1
        )
        XCTAssertTrue(
            SuggestedReplyPrompt.instructions.contains(
                "Ground reply substance and direction using this priority")
        )
        XCTAssertTrue(
            SuggestedReplyPrompt.instructions.contains(
                "recentMessages and existingHistorySummary/olderMessagesToSummarize")
        )
        XCTAssertTrue(
            SuggestedReplyPrompt.instructions.contains(
                "Ground wording and style using this priority")
        )
        XCTAssertTrue(
            SuggestedReplyPrompt.instructions.contains(
                "persona instructions; protected active persona observations; mutable active persona observations")
        )
        let exampleData = try XCTUnwrap(
            SuggestedReplyPrompt.canonicalJSONExample.data(using: .utf8))
        let example = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exampleData) as? [String: Any])
        XCTAssertFalse(try XCTUnwrap(example["historySummary"] as? String).isEmpty)
        XCTAssertEqual(try XCTUnwrap(example["replies"] as? [String]).count, 2)
        XCTAssertFalse(try XCTUnwrap(example["conversationStrategy"] as? String).isEmpty)
        XCTAssertFalse(try XCTUnwrap(example["strategyRationale"] as? String).isEmpty)
        let exampleChanges = try XCTUnwrap(example["memoryChanges"] as? [[String: Any]])
        XCTAssertEqual(exampleChanges.first?["action"] as? String, "add")
        XCTAssertTrue(exampleChanges.first?["targetMemoryID"] is NSNull)
        XCTAssertNil(exampleChanges.first?["kind"])
        XCTAssertNotNil(
            UUID(
                uuidString: try XCTUnwrap(
                    (exampleChanges.first?["evidenceMessageIDs"] as? [String])?.first)))
        let exampleObservations = try XCTUnwrap(
            example["personaObservationChanges"] as? [[String: Any]])
        XCTAssertEqual(exampleObservations.first?["action"] as? String, "add")
        XCTAssertTrue(exampleObservations.first?["targetObservationID"] is NSNull)

        let schemaData = try JSONSerialization.data(withJSONObject: SuggestedReplyPrompt.jsonSchema)
        let schemaText = try XCTUnwrap(String(data: schemaData, encoding: .utf8))
        XCTAssertFalse(schemaText.contains("uniqueItems"))
        let rootProperties = try XCTUnwrap(
            SuggestedReplyPrompt.jsonSchema["properties"] as? [String: Any]
        )
        XCTAssertEqual(
            Set(rootProperties.keys),
            [
                "historySummary", "replies", "conversationStrategy", "strategyRationale",
                "memoryChanges", "personaObservationChanges"
            ]
        )
        let memoryChangesSchema = try XCTUnwrap(rootProperties["memoryChanges"] as? [String: Any])
        let memoryItemSchema = try XCTUnwrap(memoryChangesSchema["items"] as? [String: Any])
        XCTAssertNil(memoryItemSchema["anyOf"])
        XCTAssertEqual(
            Set(try XCTUnwrap(memoryItemSchema["required"] as? [String])),
            ["action", "targetMemoryID", "text", "evidenceMessageIDs"]
        )
        let observationSchema = try XCTUnwrap(
            rootProperties["personaObservationChanges"] as? [String: Any])
        let observationItem = try XCTUnwrap(observationSchema["items"] as? [String: Any])
        XCTAssertEqual(
            Set(try XCTUnwrap(observationItem["required"] as? [String])),
            ["action", "targetObservationID", "text", "evidenceMessageIDs"]
        )

        let decodedExample = try SuggestedReplyResultDecoder.decode(
            content: SuggestedReplyPrompt.canonicalJSONExample,
            finishReason: "stop"
        )
        XCTAssertEqual(decodedExample.memoryChanges.count, 1)
        XCTAssertEqual(decodedExample.personaObservationChanges.count, 1)
        XCTAssertFalse(decodedExample.conversationStrategy.isEmpty)
        XCTAssertFalse(decodedExample.strategyRationale.isEmpty)
        for value in [
            "Sarah", "Met at university", "Vegetarian", "Confirm dinner",
            "Warm & Collaborative", "Dinner at 7?"
        ] {
            XCTAssertTrue(prompt.contains(value), "Missing reply grounding: \(value)")
        }
        XCTAssertTrue(prompt.contains(#""certainty":"userConfirmed""#))
        XCTAssertTrue(prompt.contains("activeObservations"))
        XCTAssertTrue(prompt.contains("maxActiveObservations"))
        XCTAssertTrue(prompt.contains("previousConversationStrategy"))
        XCTAssertTrue(prompt.hasPrefix("<conversation_data>"))
        XCTAssertTrue(prompt.hasSuffix("</conversation_data>"))
        XCTAssertFalse(prompt.contains("Archived detail"))
        XCTAssertTrue(prompt.contains(#""origin":"user""#))
        XCTAssertFalse(prompt.contains(#""memoryChanges":[]"#))

        let continuityPrompt = SuggestedReplyPrompt.input(
            for: makeReplyRequest(previousConversationStrategy: "Move toward confirming dinner.")
        )
        XCTAssertTrue(
            continuityPrompt.contains(#""previousConversationStrategy":"Move toward confirming dinner.""#)
        )

        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content:
                    "{\"historySummary\":\"\",\"replies\":[\"Same\",\"Same\"],\"memoryChanges\":[]}",
                finishReason: "stop"
            )
        )
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content:
                    "{\"historySummary\":\"\",\"replies\":[\"Only one\"],\"memoryChanges\":[]}",
                finishReason: "stop"
            )
        )

        let normalized = try SuggestedReplyResultDecoder.decode(
            content:
                "Here is the requested JSON:\n{\"history_summary\":\"Earlier context\",\"suggestedReplies\":[{\"text\":\"First\"},{\"reply\":\"Second\"}],\"conversationStrategy\":\"Keep the exchange moving.\",\"strategyRationale\":\"The latest message is actionable.\",\"memoryChanges\":[],\"personaObservationChanges\":[]}",
            finishReason: "stop"
        )
        XCTAssertEqual(normalized.historySummary, "Earlier context")
        XCTAssertEqual(normalized.replies, ["First", "Second"])

        let fallback = try SuggestedReplyResultDecoder.decode(
            content:
                "{\"historySummary\":null,\"reply1\":\"First\",\"reply2\":\"Second\",\"conversationStrategy\":\"Keep the exchange moving.\",\"strategyRationale\":\"The latest message is actionable.\",\"memoryChanges\":[],\"personaObservationChanges\":[]}",
            finishReason: "stop",
            historySummaryFallback: "Saved summary"
        )
        XCTAssertEqual(fallback.historySummary, "Saved summary")
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content:
                    "{\"historySummary\":null,\"replies\":[\"First\",\"Second\"],\"memoryChanges\":[]}",
                finishReason: "stop"
            )
        )

        let messageID = UUID()
        let memoryID = UUID()
        let withChange = try SuggestedReplyResultDecoder.decode(
            content: """
                {"historySummary":"","replies":["First","Second"],"conversationStrategy":"Keep the exchange moving.","strategyRationale":"The latest message is actionable.","memoryChanges":[{"action":"update","targetMemoryID":"\(memoryID.uuidString)","text":"Now lives in Berlin","evidenceMessageIDs":["\(messageID.uuidString)"]}],"personaObservationChanges":[]}
                """,
            finishReason: "stop"
        )
        XCTAssertEqual(withChange.memoryChanges.first?.targetMemoryID, memoryID)
        XCTAssertEqual(withChange.memoryChanges.first?.sourceMessageIDs, [messageID])

        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content:
                    "{\"historySummary\":\"\",\"replies\":[\"First\",\"Second\"],\"memoryChanges\":[{\"action\":\"add\",\"targetMemoryID\":null,\"text\":\"Vegetarian\",\"evidenceMessageIDs\":[\"not-a-uuid\"]}],\"personaObservationChanges\":[]}",
                finishReason: "stop"
            )
        )
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content:
                    "{\"historySummary\":\"\",\"replies\":[\"First\",\"Second\"],\"conversationStrategy\":\"\",\"strategyRationale\":\"The latest message is actionable.\",\"memoryChanges\":[],\"personaObservationChanges\":[]}",
                finishReason: "stop"
            )
        )
    }

    @MainActor
    func testOpenAISendsBase64ImageWithStructuredOutputAndNoOCRTranscript() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validAnalysisJSON(matchedChatID: "sarah-jenkins")))
        ]

        _ = try await OpenAIClient(session: makeSession()).analyzeChatScreenshot(
            makeMultiImageRequest(),
            apiKey: "open-key",
            model: .gpt54Mini
        )

        let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/responses")
        let body = try jsonBody(request)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(
            ((body["text"] as? [String: Any])?["format"] as? [String: Any])?["type"] as? String,
            "json_schema")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let images = content.filter { $0["type"] as? String == "input_image" }
        XCTAssertEqual(images.count, 2)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image["detail"] as? String, "high")
        XCTAssertTrue(
            try XCTUnwrap(image["image_url"] as? String).hasPrefix("data:image/png;base64,"))
        XCTAssertTrue(
            try XCTUnwrap(images.last?["image_url"] as? String).hasPrefix(
                "data:image/jpeg;base64,"))
        let prompt = try XCTUnwrap(
            content.first { $0["type"] as? String == "input_text" }?["text"] as? String)
        XCTAssertFalse(prompt.contains("OCR observations"))
        XCTAssertTrue(
            try XCTUnwrap(body["instructions"] as? String).contains("Literal visual observations"))
    }

    @MainActor
    func testZAIAnalysisUsesRegionalEndpointsWithoutJSONMode() async throws {
        let cases: [(ZAIClient.Region, String)] = [
            (.international, "api.z.ai"),
            (.china, "open.bigmodel.cn")
        ]
        let models: [ProviderModel] = [.glm46VFlashX]

        for (region, host) in cases {
            for model in models {
                AnalysisURLProtocolStub.responses = [
                    (
                        200,
                        zaiResponse(
                            content: validAnalysisJSON(
                                matchedChatID: nil,
                                includeQuotedReply: false
                            )
                        )
                    )
                ]
                let result = try await ZAIClient(region: region, session: makeSession())
                    .analyzeChatScreenshot(
                        makeMultiImageRequest(), apiKey: "regional-key", model: model
                    )
                XCTAssertNil(result.messages.first?.quotedReply)

                let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.last)
                XCTAssertEqual(request.url?.host, host)
                XCTAssertEqual(request.url?.path, "/api/paas/v4/chat/completions")
                let body = try jsonBody(request)
                XCTAssertEqual(body["model"] as? String, model.rawValue)
                XCTAssertNil(body["response_format"])
                XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
                XCTAssertEqual(body["do_sample"] as? Bool, false)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertTrue(
                    try XCTUnwrap(messages.first?["content"] as? String).contains(
                        "Literal visual observations"))
                let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
                let images = userContent.filter { $0["type"] as? String == "image_url" }
                XCTAssertEqual(images.count, 2)
                let image = try XCTUnwrap(images.first)
                let imageURL = try XCTUnwrap(
                    (image["image_url"] as? [String: Any])?["url"] as? String)
                XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
                let secondImageURL = try XCTUnwrap(
                    (images.last?["image_url"] as? [String: Any])?["url"] as? String)
                XCTAssertTrue(secondImageURL.hasPrefix("data:image/jpeg;base64,"))
            }
        }
    }

    @MainActor
    func testDiagnosticsDoNotContainImageKeyOrChatContent() async throws {
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: validAnalysisJSON(matchedChatID: nil)))
        ]

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

    @MainActor
    func testOpenAIGeneratesRepliesWithTextOnlyStrictOutput() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validRepliesJSON()))
        ]

        let result = try await OpenAIClient(session: makeSession()).generateSuggestedReplies(
            makeReplyRequest(), apiKey: "key", model: .gpt54Mini
        )

        XCTAssertEqual(
            result.replies, ["Sounds good to me.", "That works — looking forward to it!"])
        let body = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(body["model"] as? String, "gpt-5.4-mini")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 3_200)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertNil(content.first { $0["type"] as? String == "input_image" })
        XCTAssertNotNil(content.first { $0["type"] as? String == "input_text" })
    }

    @MainActor
    func testOpenAIAndZAINormalizeTheSameLearningContract() async throws {
        let memoryEvidenceID = UUID()
        let personaEvidenceID = UUID()
        let secondPersonaEvidenceID = UUID()
        let content = """
            {"historySummary":null,"replies":["First reply","Second reply"],
             "conversationStrategy":"Answer directly and keep the next step open.",
             "strategyRationale":"The supplied messages are enough for a concise reply and style learning.",
             "memoryChanges":[
              {"action":"add","targetMemoryID":null,"text":"Prefers vegetarian restaurants","evidenceMessageIDs":["\(memoryEvidenceID.uuidString)"]}
             ],
             "personaObservationChanges":[
              {"action":"add","targetObservationID":null,"text":"Often omits final punctuation.","evidenceMessageIDs":["\(personaEvidenceID.uuidString)","\(secondPersonaEvidenceID.uuidString)"]}
             ]}
            """

        AnalysisURLProtocolStub.responses = [(200, openAIResponse(content: content))]
        let openAIResult = try await OpenAIClient(session: makeSession()).generateSuggestedReplies(
            makeReplyRequest(), apiKey: "key", model: .gpt54Mini
        )

        AnalysisURLProtocolStub.reset()
        AnalysisURLProtocolStub.responses = [(200, zaiResponse(content: content))]
        let zaiResult = try await ZAIClient(region: .international, session: makeSession())
            .generateSuggestedReplies(makeReplyRequest(), apiKey: "key", model: .glm47FlashX)

        XCTAssertEqual(openAIResult, zaiResult)
        XCTAssertEqual(openAIResult.memoryChanges.first?.sourceMessageIDs, [memoryEvidenceID])
        XCTAssertEqual(
            openAIResult.personaObservationChanges.map(\.text), ["Often omits final punctuation."])
    }

    @MainActor
    func testZAIFailsReplyGenerationAfterOneMalformedResponse() async throws {
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, zaiResponse(content: "{}")),
            (200, zaiResponse(content: validRepliesJSON()))
        ]

        do {
            _ = try await ZAIClient(
                region: .international,
                session: makeSession(),
                eventReporter: reporter
            ).generateSuggestedReplies(makeReplyRequest(), apiKey: "key", model: .glm47FlashX)
            XCTFail("Expected malformed suggested replies to fail")
        } catch let error as ProviderConnectionError {
            guard case .structuredOutput(let details) = error else {
                return XCTFail("Expected structured-output failure, got \(error)")
            }
            XCTAssertEqual(details.failure.kind, .schemaMismatch)
        } catch {
            XCTFail("Expected provider failure, got \(error)")
        }

        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: reporter.events), [1])
        let body = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(body["model"] as? String, "glm-4.7-flashx")
        XCTAssertEqual(body["max_tokens"] as? Int, 3_200)
        XCTAssertEqual(
            (body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue(messages.allSatisfy { $0["content"] is String })
    }

    private var screenshotData: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    }

    private var secondScreenshotData: Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
    }

    private func makeReplyRequest(
        previousConversationStrategy: String? = nil
    ) -> SuggestedReplyGenerationRequest {
        SuggestedReplyGenerationRequest(
            chatName: "Sarah",
            contactMemories: [
                ContactMemory(text: "Met at university"),
                ContactMemory(text: "Vegetarian"),
                ContactMemory(text: "Archived detail", status: .archived)
            ],
            currentInteractionGoal: "Confirm dinner",
            persona: PersonaPromptContext(
                id: UUID(), name: "Warm & Collaborative",
                instructions: "Write warmly and collaboratively.", observations: [],
                protectedTombstones: []
            ),
            personaLearningMessages: [],
            existingHistorySummary: "",
            summaryMode: .unchanged,
            olderMessagesToSummarize: [],
            recentMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(),
                    sender: "contact", senderName: "Sarah", text: "Dinner at 7?",
                    timeLabel: "6:00 PM"
                )
            ],
            previousConversationStrategy: previousConversationStrategy,
            traceID: ImportTraceID()
        )
    }

    private func validRepliesJSON() -> String {
        "{\"historySummary\":null,\"replies\":[\"Sounds good to me.\",\"That works — looking forward to it!\"],\"conversationStrategy\":\"Confirm the plan now, then move toward logistics if they stay positive.\",\"strategyRationale\":\"The latest message asks for confirmation, so a concise yes keeps momentum without adding unsupported details.\",\"memoryChanges\":[],\"personaObservationChanges\":[]}"
    }

    private func makeRequest() -> ChatScreenshotAnalysisRequest {
        ChatScreenshotAnalysisRequest(
            imageData: screenshotData,
            candidates: [
                ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
            ]
        )
    }

    private func makeMultiImageRequest() -> ChatScreenshotAnalysisRequest {
        ChatScreenshotAnalysisRequest(
            imageDataList: [screenshotData, secondScreenshotData],
            candidates: [
                ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
            ]
        )
    }

    private func validAnalysisJSON(
        matchedChatID: String?,
        includeQuotedReply: Bool = true
    ) -> String {
        var message: [String: Any] = [
            "sender": "contact",
            "senderName": "Sarah Jenkins",
            "text": "Can we meet tomorrow?",
            "timestampLabel": "10:42 AM",
            "outerAlignment": "left",
            "outerAuthorLabel": NSNull(),
            "senderConfidence": 0.95,
            "senderEvidence": "alignment_convention"
        ]
        if includeQuotedReply {
            message["quotedReply"] = NSNull()
        }
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
            "messages": [
                message
            ],
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
            "choices": [
                [
                    "message": ["content": content.map { $0 as Any } ?? NSNull()],
                    "finish_reason": finishReason
                ]
            ]
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
