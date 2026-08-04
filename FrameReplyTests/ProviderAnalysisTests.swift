import Foundation
import XCTest

@testable import FrameReply

final class ProviderAnalysisTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnalysisURLProtocolStub.reset()
    }

    func testFiveContractsHaveExactClosedRootKeys() throws {
        XCTAssertEqual(ChatImportPrompt.screenshotImportVersion, 1)
        XCTAssertEqual(ChatImportPrompt.textImportVersion, 1)
        XCTAssertEqual(SuggestedReplyPrompt.version, 5)

        let screenshot = ChatImportPrompt.contract(for: makeRequest())
        let shared = ChatImportPrompt.contract(
            for: ChatImportAnalysisRequest(transcriptItems: ["Alice: Hi"], candidates: []))
        let standard = SuggestedReplyPrompt.contract(for: .standard, appLanguage: "en")
        let drafting = SuggestedReplyPrompt.contract(for: .drafting, appLanguage: "en")
        let persona = SuggestedReplyPrompt.contract(
            for: .personaStyleLearning, appLanguage: "en")

        try assertContract(
            screenshot,
            keys: [
                "extractionStatus", "conversationTitle", "conversationKind", "titleSource",
                "ownershipConvention", "messages", "matchedChatID", "matchConfidence"
            ], version: ChatImportPrompt.screenshotImportVersion)
        try assertContract(
            shared,
            keys: [
                "extractionStatus", "conversationTitle", "conversationKind", "titleSource",
                "messages", "matchedChatID", "matchConfidence"
            ], version: ChatImportPrompt.textImportVersion)
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
        XCTAssertTrue(
            standard.instructions.contains(
                "Write conversationStrategy, strategyRationale, and every non-null personaObservationChanges.text in English (en), regardless of the language in conversation_data."
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "Match each reply to the language and script of the latest relevant conversation messages."
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "Match historySummary to the messages it summarizes and every non-null memoryChanges.text to its cited evidence."
            )
        )
        XCTAssertTrue(standard.instructions.contains("use the dominant relevant one"))
        XCTAssertTrue(
            standard.instructions.contains("Preserve proper names, URLs, and identifiers"))
        XCTAssertTrue(standard.instructions.contains("For reply bodies only"))
        XCTAssertFalse(standard.instructions.contains("maximum of 120 Unicode code points"))
        XCTAssertFalse(standard.instructions.contains("maximum of 240 Unicode code points"))
        XCTAssertTrue(
            standard.instructions.contains(
                "understood without reopening the source messages"
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "Summarize the item in new wording"
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "Do not quote or reproduce the source, write a keyword list"
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "must be confirmed by the other participant"
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "do not rewrite them merely to translate or shorten them"
            )
        )
        XCTAssertTrue(
            drafting.instructions.contains(
                "Write conversationStrategy and strategyRationale in English (en), regardless of the language in conversation_data."
            )
        )
        XCTAssertTrue(
            drafting.instructions.contains(
                "Match each reply to the language and script of the latest relevant conversation messages"
            )
        )
        for instructions in [standard.instructions, drafting.instructions] {
            XCTAssertEqual(
                instructions.components(separatedBy: "Sender and turn rules").count - 1,
                1
            )
            for rule in [
                #"Sender roles are relative to the intended reply author: "user" is that person"#,
                #"Latest "other_participant" or "group_participant": return exactly two replies"#,
                "Otherwise return replies [], including uncertain completion or a style-only draftingInput",
                "omits the wait instruction, and does not predict the response",
                #"without misattributing "user" messages"#
            ] {
                XCTAssertTrue(instructions.contains(rule), rule)
            }
        }
        XCTAssertTrue(
            standard.instructions.contains(
                "conversationStrategy is a concise direction for the next 1–3 conversational turns"
            )
        )
        XCTAssertTrue(
            standard.instructions.contains(
                "strategyRationale is a concise user-facing explanation of evidence, assumptions, and uncertainty"
            )
        )
        XCTAssertFalse(standard.instructions.contains("only decisive conversation evidence"))
        XCTAssertFalse(standard.instructions.contains("material uncertainty"))
        XCTAssertFalse(drafting.instructions.contains("Strategy rules"))
        XCTAssertTrue(
            persona.instructions.contains(
                "Write every non-null personaObservationChanges.text in English (en), regardless of the language in conversation_data."
            )
        )
        for contract in [standard, drafting, persona] {
            XCTAssertEqual(
                contract.instructions.components(separatedBy: "English (en)").count - 1,
                1
            )
            XCTAssertFalse(contract.instructions.contains("appLanguage"))
            XCTAssertFalse(contract.instructions.lowercased().contains("app-owned"))
            XCTAssertFalse(contract.instructions.contains("silently verify"))
        }

        let memoryChanges = try XCTUnwrap(
            summaryProperties["memoryChanges"] as? [String: Any]
        )
        let memoryItems = try XCTUnwrap(memoryChanges["items"] as? [String: Any])
        let memoryProperties = try XCTUnwrap(
            memoryItems["properties"] as? [String: Any]
        )
        let memoryText = try XCTUnwrap(memoryProperties["text"] as? [String: Any])
        XCTAssertEqual(
            memoryText["maxLength"] as? Int,
            ChatMemoryLimits.maximumAITextCodePoints
        )
        XCTAssertNil(memoryText["description"])

        let observationChanges = try XCTUnwrap(
            summaryProperties["personaObservationChanges"] as? [String: Any]
        )
        let observationItems = try XCTUnwrap(
            observationChanges["items"] as? [String: Any]
        )
        let observationProperties = try XCTUnwrap(
            observationItems["properties"] as? [String: Any]
        )
        let observationText = try XCTUnwrap(
            observationProperties["text"] as? [String: Any]
        )
        XCTAssertEqual(
            observationText["maxLength"] as? Int,
            PersonaLimits.maximumObservationTextCodePoints
        )
        XCTAssertNil(observationText["description"])

        let strategy = try XCTUnwrap(
            summaryProperties["conversationStrategy"] as? [String: Any]
        )
        XCTAssertEqual(
            strategy["maxLength"] as? Int,
            SuggestedReplyTextLimits.conversationStrategyMaximumCodePoints
        )
        XCTAssertNil(strategy["description"])
        let rationale = try XCTUnwrap(
            summaryProperties["strategyRationale"] as? [String: Any]
        )
        XCTAssertEqual(
            rationale["maxLength"] as? Int,
            SuggestedReplyTextLimits.strategyRationaleMaximumCodePoints
        )
        XCTAssertNil(rationale["description"])
        XCTAssertEqual(
            summarySchema["description"] as? String,
            "Updated compact older-message context, or null when no safe update is available."
        )
        let replies = try XCTUnwrap(summaryProperties["replies"] as? [String: Any])
        XCTAssertNil(replies["description"])
    }

    func testTaskInputsContainOnlyDataUsedByTheirContract() {
        let standard = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .standard))
        XCTAssertTrue(standard.contains("chatMemories"))
        XCTAssertTrue(standard.contains("personaLearningMessages"))
        XCTAssertTrue(standard.contains("recentMessages"))
        XCTAssertTrue(standard.contains("<text_length_limits>"))
        XCTAssertTrue(
            standard.contains(
                "strategyRationale: maximum 450 Unicode code points"))
        XCTAssertTrue(
            standard.contains(
                "Each non-null memoryChanges.text: maximum 120 Unicode code points"))
        XCTAssertTrue(
            standard.contains(
                "Each non-null personaObservationChanges.text: maximum 240 Unicode code points"))
        XCTAssertFalse(standard.contains("exactly one short sentence"))
        XCTAssertFalse(standard.contains("do not instruct the user to wait"))
        XCTAssertFalse(standard.contains("appLanguage"))
        XCTAssertFalse(standard.contains("presentationLanguageIdentifier"))
        for removed in ["chatName", "personaName", "certainty", "origin"] {
            XCTAssertFalse(standard.contains("\"\(removed)\""))
        }

        let drafting = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .drafting))
        XCTAssertTrue(drafting.contains("draftingInput"))
        XCTAssertTrue(drafting.contains("recentMessages"))
        XCTAssertTrue(drafting.contains("<text_length_limits>"))
        XCTAssertFalse(drafting.contains("appLanguage"))
        XCTAssertFalse(drafting.contains("personaLearningMessages"))
        XCTAssertFalse(drafting.contains("summaryMode"))

        let persona = SuggestedReplyPrompt.input(
            for: makeReplyRequest(task: .personaStyleLearning))
        XCTAssertTrue(persona.contains("personaLearningMessages"))
        XCTAssertTrue(persona.contains("activeObservations"))
        XCTAssertFalse(persona.contains("appLanguage"))
        XCTAssertFalse(persona.contains("recentMessages"))
        XCTAssertFalse(persona.contains("chatMemories"))
        XCTAssertFalse(persona.contains("draftingInput"))
        XCTAssertTrue(persona.contains("<text_length_limits>"))
        XCTAssertTrue(
            persona.contains(
                "Each non-null personaObservationChanges.text: maximum 240 Unicode code points"))
    }

    func testProviderSchemaPreservesCanonicalSchemaAndHumanizesOnlyTextLengths() throws {
        let contract = SuggestedReplyPrompt.contract(for: .standard, appLanguage: "en")
        let canonicalBefore = try schemaText(contract.schema)

        let providerSchema = contract.providerSchema
        let providerProperties = try XCTUnwrap(
            providerSchema["properties"] as? [String: Any]
        )
        let providerStrategy = try XCTUnwrap(
            providerProperties["conversationStrategy"] as? [String: Any]
        )
        XCTAssertNil(providerStrategy["minLength"])
        XCTAssertNil(providerStrategy["maxLength"])
        let strategyDescription = try XCTUnwrap(
            providerStrategy["description"] as? String)
        XCTAssertEqual(
            strategyDescription.components(
                separatedBy: "300 Unicode code points"
            ).count - 1,
            1
        )
        XCTAssertTrue(
            strategyDescription.contains("Minimum length: 1 Unicode code point"))

        let providerReplies = try XCTUnwrap(
            providerProperties["replies"] as? [String: Any]
        )
        XCTAssertEqual(providerReplies["minItems"] as? Int, 0)
        XCTAssertEqual(providerReplies["maxItems"] as? Int, 2)
        XCTAssertNil(providerReplies["description"])
        let replyItems = try XCTUnwrap(providerReplies["items"] as? [String: Any])
        XCTAssertNil(replyItems["minLength"])
        XCTAssertNil(replyItems["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(replyItems["description"] as? String).contains(
                "Maximum length: 500 Unicode code points")
        )

        let providerMemoryChanges = try XCTUnwrap(
            providerProperties["memoryChanges"] as? [String: Any])
        XCTAssertEqual(providerMemoryChanges["maxItems"] as? Int, 8)
        let providerMemoryItems = try XCTUnwrap(
            providerMemoryChanges["items"] as? [String: Any])
        let providerMemoryProperties = try XCTUnwrap(
            providerMemoryItems["properties"] as? [String: Any])
        let providerMemoryText = try XCTUnwrap(
            providerMemoryProperties["text"] as? [String: Any])
        XCTAssertNil(providerMemoryText["maxLength"])
        XCTAssertEqual(
            providerMemoryText["description"] as? String,
            "Maximum length: 120 Unicode code points."
        )

        XCTAssertEqual(contract.instructions(for: .nativeJSONSchema), contract.instructions)
        XCTAssertTrue(
            contract.instructions(for: .promptedJSONObject).contains(
                "Maximum length: 450 Unicode code points"))
        XCTAssertEqual(try schemaText(contract.schema), canonicalBefore)
    }

    func testSuggestedReplyContractsResolveAppLanguageForMixedLanguageData() throws {
        for task in [
            SuggestedReplyTask.standard, .drafting, .personaStyleLearning
        ] {
            let englishSchema = try schemaText(
                SuggestedReplyPrompt.contract(for: task, appLanguage: "en").schema)
            for (identifier, descriptor) in [
                ("en", "English (en)"),
                ("en-US", "English (United States) (en-US)"),
                ("zh-Hans", "Chinese, Simplified (zh-Hans)")
            ] {
                let contract = SuggestedReplyPrompt.contract(
                    for: task, appLanguage: identifier)
                XCTAssertEqual(
                    contract.instructions.components(separatedBy: descriptor).count - 1,
                    1,
                    identifier
                )
                let schema = try schemaText(contract.schema)
                XCTAssertEqual(schema, englishSchema, identifier)
                XCTAssertFalse(schema.contains(descriptor), identifier)
            }
        }

        let mixedLanguageRequests = [
            makeReplyRequest(
                task: .standard, recentMessageText: "晚饭七点？",
                personaLearningText: "当然"),
            makeReplyRequest(
                task: .drafting, recentMessageText: "明日の七時？",
                personaLearningText: "もちろん"),
            makeReplyRequest(
                task: .personaStyleLearning, recentMessageText: "¿Cena a las siete?",
                personaLearningText: "Claro")
        ]
        for request in mixedLanguageRequests {
            let contract = SuggestedReplyPrompt.contract(
                for: request.task, appLanguage: request.appLanguage)
            let input = SuggestedReplyPrompt.input(for: request)
            XCTAssertTrue(contract.instructions.contains("English (en)"))
            XCTAssertFalse(input.contains("appLanguage"))
        }
        XCTAssertTrue(SuggestedReplyPrompt.input(for: mixedLanguageRequests[0]).contains("晚饭七点？"))
        XCTAssertTrue(SuggestedReplyPrompt.input(for: mixedLanguageRequests[1]).contains("明日の七時？"))
        XCTAssertTrue(SuggestedReplyPrompt.input(for: mixedLanguageRequests[2]).contains("Claro"))
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
            "suggested_reply_drafting-v5-gpt-5.6-luna-en")
        XCTAssertTrue(
            try XCTUnwrap(replyBody["instructions"] as? String).contains(
                "Write conversationStrategy and strategyRationale in English (en)")
        )
        let schema = try XCTUnwrap(replyFormat["schema"] as? [String: Any])
        let replyProperties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(
            Set(replyProperties.keys),
            ["replies", "conversationStrategy", "strategyRationale"])
        let strategySchema = try XCTUnwrap(
            replyProperties["conversationStrategy"] as? [String: Any]
        )
        XCTAssertNil(strategySchema["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(strategySchema["description"] as? String).contains(
                "Maximum length: 300 Unicode code points"))
        let replyItems = try XCTUnwrap(
            replyProperties["replies"] as? [String: Any]
        )
        XCTAssertEqual(replyItems["minItems"] as? Int, 0)
        XCTAssertEqual(replyItems["maxItems"] as? Int, 2)
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
    func testOpenRouterPinsQwenAndUsesStrictPrivateRoutingForScreenshots() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: validScreenshotAnalysisJSON()))
        ]

        let result = try await OpenRouterClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "sk-or-test", model: .qwen37Plus)

        XCTAssertEqual(result.messages.map(\.text), ["Hello"])
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        let body = try jsonBody(request)
        XCTAssertEqual(body["model"] as? String, "qwen/qwen3.7-plus")
        let routing = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(routing["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(routing["require_parameters"] as? Bool, true)
        XCTAssertEqual(routing["data_collection"] as? String, "deny")
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first { $0["type"] as? String == "image_url" })
        let imageURL = try XCTUnwrap(image["image_url"] as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(imageURL["url"] as? String).hasPrefix("data:image/png;base64,"))
    }

    @MainActor
    func testOpenRouterAcceptsSemanticRecoveryButRejectsExtraFieldsWithoutRetry() async throws {
        var recoverable = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(validScreenshotAnalysisJSON().utf8))
                as? [String: Any]
        )
        recoverable["conversationTitle"] = ""
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: jsonString(recoverable)))
        ]

        _ = try await OpenRouterClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .qwen37Plus)

        AnalysisURLProtocolStub.reset()
        var output = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(validScreenshotAnalysisJSON().utf8))
                as? [String: Any]
        )
        output["extra"] = true
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: jsonString(output)))
        ]

        await assertThrowsErrorAsync {
            _ = try await OpenRouterClient(session: self.makeSession()).analyzeChatScreenshot(
                self.makeRequest(), apiKey: "key", model: .qwen37Plus)
        }
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
    }

    @MainActor
    func testOpenRouterUsesStructuralSchemaProjectionForSuggestedReplies() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: validDraftingJSON()))
        ]

        _ = try await OpenRouterClient(session: makeSession()).generateSuggestedReplies(
            makeReplyRequest(task: .drafting), apiKey: "key", model: .qwen37Plus)

        let body = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let strategy = try XCTUnwrap(
            properties["conversationStrategy"] as? [String: Any]
        )
        XCTAssertNil(strategy["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(strategy["description"] as? String).contains(
                "Maximum length: 300 Unicode code points"))
        XCTAssertEqual(
            (body["provider"] as? [String: Any])?["require_parameters"] as? Bool,
            true
        )
    }

    func testSuggestedReplyDecoderRecoversOptionalAnalysisFieldsAndPreservesCoreReplies() throws {
        let content = jsonString([
            "historySummary": 42,
            "replies": [" First ", " Second "],
            "conversationStrategy": " Continue after they respond. ",
            "strategyRationale": " The response determines the next step. ",
            "memoryChanges": "invalid",
            "extra": true
        ])
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: "Result:\n\(content)", finishReason: "stop", task: .standard)

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.replies, ["First", "Second"])
        XCTAssertNil(decoded.value.historySummary)
        XCTAssertEqual(decoded.value.conversationStrategy, "Continue after they respond.")
        XCTAssertEqual(decoded.value.strategyRationale, "The response determines the next step.")
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
        let wait = try SuggestedReplyResultDecoder.decode(
            content: jsonString([
                "historySummary": NSNull(),
                "replies": [],
                "conversationStrategy": "After a response, continue with the current topic.",
                "strategyRationale": "The future response determines the useful next step.",
                "memoryChanges": [],
                "personaObservationChanges": []
            ]),
            finishReason: "stop",
            task: .standard
        )
        XCTAssertTrue(wait.replies.isEmpty)
        for invalidReplies: [Any] in [
            ["only one"],
            ["same", " same "],
            ["one", "two", "three"]
        ] {
            XCTAssertThrowsError(
                try SuggestedReplyResultDecoder.decode(
                    content: jsonString([
                        "historySummary": NSNull(),
                        "replies": invalidReplies,
                        "conversationStrategy": "Continue.",
                        "strategyRationale": "The context supports continuing.",
                        "memoryChanges": [],
                        "personaObservationChanges": []
                    ]),
                    finishReason: "stop",
                    task: .standard
                )
            )
        }
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: jsonString([
                    "historySummary": NSNull(),
                    "replies": [],
                    "conversationStrategy": "",
                    "strategyRationale": "The response determines the next step.",
                    "memoryChanges": [],
                    "personaObservationChanges": []
                ]),
                finishReason: "stop",
                task: .standard
            )
        )
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: "\(valid)\n\(valid)", finishReason: "stop", task: .standard))
    }

    func testSuggestedReplyDecoderUsesUnicodeCodePointLimits() throws {
        let exactStrategy = String(repeating: "s", count: 300)
        let exactRationale = String(repeating: "界", count: 448) + "e\u{301}"
        XCTAssertEqual(exactRationale.count, 449)
        XCTAssertEqual(exactRationale.unicodeScalars.count, 450)

        let exact = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "historySummary": NSNull(),
                "replies": [],
                "conversationStrategy": exactStrategy,
                "strategyRationale": exactRationale,
                "memoryChanges": [],
                "personaObservationChanges": []
            ]),
            finishReason: "stop",
            task: .standard
        )
        XCTAssertFalse(exact.recovered)
        XCTAssertEqual(exact.value.conversationStrategy, exactStrategy)
        XCTAssertEqual(exact.value.strategyRationale, exactRationale)

        let precomposed = String(repeating: "é", count: 450)
        XCTAssertEqual(precomposed.count, 450)
        XCTAssertEqual(precomposed.unicodeScalars.count, 450)
        let precomposedResult = try SuggestedReplyResultDecoder.decode(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": precomposed
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(precomposedResult.strategyRationale, precomposed)

        let overlongCombining = String(repeating: "界", count: 449) + "e\u{301}"
        XCTAssertEqual(overlongCombining.count, 450)
        XCTAssertEqual(overlongCombining.unicodeScalars.count, 451)
        let recovered = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": overlongCombining
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertTrue(recovered.recovered)
        XCTAssertEqual(recovered.value.strategyRationale, String(repeating: "界", count: 449))
        XCTAssertEqual(
            recovered.fieldRecoveries,
            [
                StructuredOutputFieldRecovery(
                    path: "strategyRationale",
                    originalCodePointCount: 451,
                    finalCodePointCount: 449
                )
            ]
        )

        let completeStrategy = String(repeating: "s", count: 280) + "."
        let recoveredStrategy = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": completeStrategy + String(repeating: "t", count: 40),
                "strategyRationale": "The latest message determines the next step."
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(recoveredStrategy.value.conversationStrategy, completeStrategy)
        XCTAssertEqual(recoveredStrategy.fieldRecoveries.first?.path, "conversationStrategy")
        XCTAssertEqual(recoveredStrategy.fieldRecoveries.first?.originalCodePointCount, 321)
        XCTAssertEqual(recoveredStrategy.fieldRecoveries.first?.finalCodePointCount, 281)
    }

    func testSuggestedReplyDecoderShortensAtSentenceThenWordBoundaryWithoutSplittingEmoji() throws {
        let completeSentence = String(repeating: "a", count: 430) + "."
        let sentenceRecovery = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": completeSentence + " " + String(repeating: "b", count: 100)
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(sentenceRecovery.value.strategyRationale, completeSentence)
        XCTAssertEqual(sentenceRecovery.value.strategyRationale.unicodeScalars.count, 431)

        let words = String(repeating: "evidence ", count: 100)
        let wordRecovery = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": words
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertTrue(wordRecovery.value.strategyRationale.hasSuffix("…"))
        XCTAssertLessThanOrEqual(
            wordRecovery.value.strategyRationale.unicodeScalars.count,
            SuggestedReplyTextLimits.strategyRationaleMaximumCodePoints
        )

        let family = "👨‍👩‍👧‍👦"
        XCTAssertGreaterThan(family.unicodeScalars.count, 1)
        let emojiRecovery = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": String(repeating: "x", count: 449) + family
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(emojiRecovery.value.strategyRationale, String(repeating: "x", count: 449))
        XCTAssertFalse(emojiRecovery.value.strategyRationale.contains("👨"))

        let cjkSentence = String(repeating: "证", count: 400) + "。"
        let cjkRecovery = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "继续。",
                "strategyRationale": cjkSentence + String(repeating: "据", count: 100)
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(cjkRecovery.value.strategyRationale, cjkSentence)
    }

    func testSuggestedReplyDecoderStillRejectsMissingEmptyAndWrongTypeStrategyFields() throws {
        for rationale: Any in [NSNull(), "", 42] {
            XCTAssertThrowsError(
                try SuggestedReplyResultDecoder.decode(
                    content: jsonString([
                        "replies": [],
                        "conversationStrategy": "Continue after a response.",
                        "strategyRationale": rationale
                    ]),
                    finishReason: "stop",
                    task: .drafting
                )
            )
        }
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: jsonString([
                    "replies": [],
                    "strategyRationale": "The latest message determines the next step."
                ]),
                finishReason: "stop",
                task: .drafting
            )
        )
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

    func testSuggestedReplyDecoderUsesSeparateMemoryAndObservationTextLimits() throws {
        let memoryEvidence = UUID()
        let personaEvidence = [UUID(), UUID()]
        let acceptedMemory = String(repeating: "界", count: 118) + "e\u{301}"
        let rejectedMemory = String(repeating: "界", count: 119) + "e\u{301}"
        XCTAssertEqual(acceptedMemory.unicodeScalars.count, 120)
        XCTAssertEqual(rejectedMemory.count, 120)
        XCTAssertEqual(rejectedMemory.unicodeScalars.count, 121)
        let acceptedObservation = String(repeating: "界", count: 240)
        let family = "👨‍👩‍👧‍👦"
        let rejectedObservation = String(repeating: "o", count: 239) + family
        XCTAssertEqual(rejectedObservation.count, 240)
        XCTAssertGreaterThan(rejectedObservation.unicodeScalars.count, 240)
        let content = jsonString([
            "historySummary": NSNull(),
            "replies": ["First", "Second"],
            "conversationStrategy": "Continue",
            "strategyRationale": "The latest message supports a direct answer.",
            "memoryChanges": [
                [
                    "action": "add", "targetMemoryID": NSNull(), "text": acceptedMemory,
                    "evidenceMessageIDs": [memoryEvidence.uuidString]
                ],
                [
                    "action": "update", "targetMemoryID": UUID().uuidString,
                    "text": rejectedMemory,
                    "evidenceMessageIDs": [memoryEvidence.uuidString]
                ]
            ],
            "personaObservationChanges": [
                [
                    "action": "add", "targetObservationID": NSNull(),
                    "text": acceptedObservation,
                    "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                ],
                [
                    "action": "add", "targetObservationID": NSNull(),
                    "text": rejectedObservation,
                    "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                ]
            ]
        ])

        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: content, finishReason: "stop", task: .standard
        )

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.memoryChanges.map(\.text), [acceptedMemory])
        XCTAssertEqual(
            decoded.value.personaObservationChanges.map(\.text),
            [acceptedObservation]
        )
        XCTAssertEqual(
            decoded.fieldRecoveries,
            [
                StructuredOutputFieldRecovery(
                    path: "memoryChanges[1].text",
                    originalCodePointCount: 121,
                    finalCodePointCount: 0
                ),
                StructuredOutputFieldRecovery(
                    path: "personaObservationChanges[1].text",
                    originalCodePointCount: rejectedObservation.unicodeScalars.count,
                    finalCodePointCount: 0
                )
            ]
        )

        let personaOnly = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "personaObservationChanges": [
                    [
                        "action": "add", "targetObservationID": NSNull(),
                        "text": rejectedObservation,
                        "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                    ]
                ]
            ]),
            finishReason: "stop",
            task: .personaStyleLearning
        )
        XCTAssertTrue(personaOnly.recovered)
        XCTAssertTrue(personaOnly.value.personaObservationChanges.isEmpty)
        XCTAssertEqual(personaOnly.fieldRecoveries.first?.finalCodePointCount, 0)
    }

    @MainActor
    func testOpenAIUsesOneStandardContractAndOneRequestForRecoveredOrFatalOutput() async throws {
        let recoveredJSON = jsonString([
            "replies": [" First ", "Second"],
            "historySummary": NSNull(),
            "conversationStrategy": "Continue after the response.",
            "strategyRationale": "The response determines the next step."
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
            "suggested_reply-v5-gpt-5.6-terra-en")
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
    func testBothMiniMaxRegionsUseM3ScreenshotWireContractAndReportUsage() async throws {
        for (region, host, provider) in [
            (MiniMaxClient.Region.international, "api.minimax.io", "miniMaxInternational"),
            (.china, "api.minimaxi.com", "miniMaxChina")
        ] {
            AnalysisURLProtocolStub.reset()
            let reporter = SpyImportEventReporter()
            AnalysisURLProtocolStub.responses = [
                (200, miniMaxResponse(content: validScreenshotAnalysisJSON(), includeUsage: true))
            ]

            let result = try await MiniMaxClient(
                region: region, session: makeSession(), eventReporter: reporter
            ).analyzeChatScreenshot(
                makeRequest(), apiKey: "key", model: .miniMaxM3)

            XCTAssertEqual(result.messages.first?.text, "Hello")
            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, host)
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try jsonBody(request)
            XCTAssertEqual(body["model"] as? String, "MiniMax-M3")
            XCTAssertEqual(body["service_tier"] as? String, "standard")
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            XCTAssertEqual(body["temperature"] as? Int, 0)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 4_000)
            XCTAssertNil(body["response_format"])

            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)
            let system = try XCTUnwrap(messages[0]["content"] as? String)
            XCTAssertTrue(system.contains("Return JSON matching this exact schema"))
            let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "image_url")
            let image = try XCTUnwrap(content.first?["image_url"] as? [String: Any])
            XCTAssertEqual(image["detail"] as? String, "high")
            XCTAssertTrue(
                try XCTUnwrap(image["url"] as? String).hasPrefix("data:image/png;base64,"))
            XCTAssertEqual(content.last?["type"] as? String, "text")
            XCTAssertEqual(providerAttempts(in: reporter.events), [1])
            XCTAssertTrue(hasValidationCategory("valid", in: reporter.events))
            XCTAssertTrue(
                reporter.events.contains { event in
                    guard
                        case .providerResponse(
                            _, let eventProvider, "MiniMax-M3", 1, _, 200, "req-test", "stop", _,
                            100, 20, 60
                        ) = event
                    else { return false }
                    return eventProvider == provider
                })
        }
    }

    @MainActor
    func testMiniMaxTranscriptAndRepliesAreTextOnlyAndUseTaskTokenCaps() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: #"{"messages":[{"text":"你好"}]}"#))
        ]
        let transcriptRequest = ChatImportAnalysisRequest(
            transcriptItems: ["Alice: 你好"], candidates: [])

        let analysis = try await MiniMaxClient(
            region: .china, session: makeSession()
        ).analyzeChatScreenshot(
            transcriptRequest, apiKey: "key", model: .miniMaxM3)

        XCTAssertEqual(analysis.messages.first?.text, "你好")
        let transcriptBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        let transcriptMessages = try XCTUnwrap(transcriptBody["messages"] as? [[String: Any]])
        XCTAssertTrue(transcriptMessages[1]["content"] is String)

        AnalysisURLProtocolStub.reset()
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: validDraftingJSON()))
        ]
        let replies = try await MiniMaxClient(
            region: .international, session: makeSession()
        ).generateSuggestedReplies(
            makeReplyRequest(task: .drafting), apiKey: "key", model: .miniMaxM3)

        XCTAssertEqual(replies.replies, ["First", "Second"])
        let replyBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(replyBody["max_completion_tokens"] as? Int, 3_200)
        XCTAssertNil(replyBody["response_format"])
        let replyMessages = try XCTUnwrap(replyBody["messages"] as? [[String: Any]])
        XCTAssertTrue(replyMessages.allSatisfy { $0["content"] is String })
        let replySystem = try XCTUnwrap(replyMessages.first?["content"] as? String)
        XCTAssertTrue(replySystem.contains("Maximum length: 450 Unicode code points"))
        let replyInput = try XCTUnwrap(replyMessages.last?["content"] as? String)
        XCTAssertTrue(replyInput.contains("<text_length_limits>"))
        XCTAssertTrue(
            replyInput.contains(
                "strategyRationale: maximum 450 Unicode code points"))
    }

    @MainActor
    func testMiniMaxReportedOverlongRationaleFixtureRecoversOnlyThatField() async throws {
        let evidenceID = UUID()
        let strategy =
            "Wait for Adel's next message; no follow-up is needed since the user's last turn already wrapped up the exchange with a clear \"See you then!\". Only reply if Adel writes again."
        let rationale =
            "The latest turn is from the user (9:50 PM), which already closed the September overlap discussion with \"See you then!\". Adel responded earlier confirming arrival after Sept 15 for 1.5+ months, and the user acknowledged that timing. Because the user's message is complete—not trailing off or asking an unresolved question—the protocol says to return replies [] rather than fabricate follow-ups. The strategy therefore focuses on waiting, and the only durable memory worth adding is Adel's confirmed Da Nang window, which is directly supported by his own message. currentInteractionGoal is empty, and no draft or style request was given, so I am not steering toward a new topic. Persona observations are unchanged because the recent messages are short and don't reveal new writing patterns beyond what's already captured."
        XCTAssertGreaterThan(rationale.unicodeScalars.count, 450)
        let payload = jsonString([
            "historySummary": NSNull(),
            "replies": [],
            "conversationStrategy": strategy,
            "strategyRationale": rationale,
            "memoryChanges": [
                [
                    "action": "add",
                    "targetMemoryID": NSNull(),
                    "text":
                        "Adel will be in Da Nang after September 15 for at least 1.5 months; tickets are not yet booked.",
                    "evidenceMessageIDs": [evidenceID.uuidString]
                ]
            ],
            "personaObservationChanges": []
        ])
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: "```json\n\(payload)\n```"))
        ]

        let result = try await MiniMaxClient(
            region: .china,
            session: makeSession(),
            eventReporter: reporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .standard),
            apiKey: "key",
            model: .miniMaxM3
        )

        XCTAssertTrue(result.replies.isEmpty)
        XCTAssertEqual(result.conversationStrategy, strategy)
        XCTAssertEqual(result.memoryChanges.count, 1)
        XCTAssertEqual(
            result.memoryChanges.first?.text,
            "Adel will be in Da Nang after September 15 for at least 1.5 months; tickets are not yet booked."
        )
        XCTAssertLessThan(
            result.strategyRationale.unicodeScalars.count,
            rationale.unicodeScalars.count
        )
        XCTAssertLessThanOrEqual(result.strategyRationale.unicodeScalars.count, 450)
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertTrue(hasValidationCategory("recovered", in: reporter.events))
    }

    @MainActor
    func testBothMiniMaxRegionsUseOneRequestForRecoveredAndFatalReplies() async throws {
        for (region, provider) in [
            (MiniMaxClient.Region.international, "miniMaxInternational"),
            (.china, "miniMaxChina")
        ] {
            AnalysisURLProtocolStub.reset()
            let recoveredReporter = SpyImportEventReporter()
            AnalysisURLProtocolStub.responses = [
                (200, miniMaxResponse(content: "Result:\n\(validStandardRepliesJSON())"))
            ]
            let recovered = try await MiniMaxClient(
                region: region, session: makeSession(), eventReporter: recoveredReporter
            ).generateSuggestedReplies(
                makeReplyRequest(task: .standard), apiKey: "key", model: .miniMaxM3)

            XCTAssertEqual(recovered.replies, ["First", "Second"])
            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            XCTAssertTrue(hasValidationCategory("recovered", in: recoveredReporter.events))
            let recoveredBody = try jsonBody(AnalysisURLProtocolStub.requests[0])
            XCTAssertNil(recoveredBody["response_format"])
            let recoveredMessages = try XCTUnwrap(
                recoveredBody["messages"] as? [[String: Any]])
            let recoveredSystem = try XCTUnwrap(
                recoveredMessages.first?["content"] as? String)
            XCTAssertTrue(
                recoveredSystem.contains("Maximum length: 120 Unicode code points"))
            XCTAssertTrue(
                recoveredSystem.contains("Maximum length: 240 Unicode code points"))
            let recoveredInput = try XCTUnwrap(
                recoveredMessages.last?["content"] as? String)
            XCTAssertTrue(
                recoveredInput.contains(
                    "Each non-null memoryChanges.text: maximum 120 Unicode code points"))
            XCTAssertTrue(
                recoveredInput.contains(
                    "Each non-null personaObservationChanges.text: maximum 240 Unicode code points"
                ))

            AnalysisURLProtocolStub.reset()
            let fatalReporter = SpyImportEventReporter()
            AnalysisURLProtocolStub.responses = [
                (200, miniMaxResponse(content: "{}")),
                (200, miniMaxResponse(content: validStandardRepliesJSON()))
            ]
            await assertThrowsErrorAsync(
                {
                    _ = try await MiniMaxClient(
                        region: region,
                        session: self.makeSession(),
                        eventReporter: fatalReporter
                    ).generateSuggestedReplies(
                        self.makeReplyRequest(task: .standard),
                        apiKey: "key",
                        model: .miniMaxM3
                    )
                },
                errorHandler: {
                    self.assertStructuredOutputError($0, provider: provider, codingPath: "root")
                })
            XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
            XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
            XCTAssertTrue(hasValidationCategory("fatal", in: fatalReporter.events))
        }
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
                    id: UUID(), sender: "user", senderName: nil,
                    text: personaLearningText, timeLabel: "")
            ],
            existingHistorySummary: existingHistorySummary,
            olderMessagesToSummarize: olderMessages,
            recentMessages: [
                SuggestedReplyPromptMessage(
                    id: UUID(), sender: "other_participant", senderName: "Sarah",
                    text: recentMessageText, timeLabel: "6:00 PM")
            ],
            draftingInput: task == .drafting ? "Make it warmer" : nil,
            previousConversationStrategy: "Confirm the plan.",
            appLanguage: appLanguage,
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

    private func openRouterResponse(content: String) -> String {
        jsonString([
            "id": "gen_test",
            "model": "qwen/qwen3.7-plus",
            "choices": [
                ["message": ["content": content], "finish_reason": "stop"]
            ]
        ])
    }

    private func miniMaxResponse(
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
