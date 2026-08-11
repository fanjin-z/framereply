import Foundation
import XCTest

@testable import FrameReply

final class ProviderClientAnalysisTests: ProviderAnalysisTestCase {
    @MainActor
    func testOpenAIUsesTaskSpecificWireContractsAndReportsUsage() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validScreenshotAnalysisJSON()))
        ]

        _ = try await OpenAIClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "key", model: .gpt56Sol
        )

        let screenshotBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(screenshotBody["store"] as? Bool, false)
        XCTAssertEqual(
            screenshotBody["prompt_cache_key"] as? String,
            "screenshot_import-v\(ChatImportPrompt.screenshotImportVersion)-gpt-5.6-sol"
        )
        let screenshotFormat = try XCTUnwrap(
            (screenshotBody["text"] as? [String: Any])?["format"] as? [String: Any]
        )
        XCTAssertEqual(screenshotFormat["type"] as? String, "json_schema")
        XCTAssertEqual(screenshotFormat["strict"] as? Bool, true)
        XCTAssertEqual(screenshotFormat["name"] as? String, "screenshot_import")
        let input = try XCTUnwrap(screenshotBody["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first { $0["type"] as? String == "input_image" })
        XCTAssertEqual(image["detail"] as? String, "high")

        AnalysisURLProtocolStub.reset()
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: validDraftingJSON(), includeUsage: true))
        ]

        let result = try await OpenAIClient(
            session: makeSession(), eventReporter: reporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .drafting), apiKey: "key", model: .gpt56Luna
        )

        XCTAssertEqual(result.replies, ["First", "Second"])
        let replyBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(
            replyBody["prompt_cache_key"] as? String,
            "suggested_reply_drafting-v\(SuggestedReplyPrompt.version)-gpt-5.6-luna-en"
        )
        let replyFormat = try XCTUnwrap(
            (replyBody["text"] as? [String: Any])?["format"] as? [String: Any]
        )
        XCTAssertEqual(replyFormat["name"] as? String, "suggested_reply_drafting")
        XCTAssertTrue(
            reporter.events.contains { event in
                guard
                    case .providerResponse(
                        _, _, _, _, _, _, _, _, _, let input, let output, let cached
                    ) = event
                else { return false }
                return input == 120 && output == 30 && cached == 80
            }
        )
    }

    @MainActor
    func testOpenRouterPinsQwenAndUsesPrivateScreenshotRouting() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: validScreenshotAnalysisJSON()))
        ]

        let result = try await OpenRouterClient(session: makeSession()).analyzeChatScreenshot(
            makeRequest(), apiKey: "sk-or-test", model: .qwen37Plus
        )

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
        XCTAssertEqual(
            (responseFormat["json_schema"] as? [String: Any])?["strict"] as? Bool,
            true
        )
    }

    @MainActor
    func testOpenRouterRecoversSingletonObjectArrayForScreenshots() async throws {
        let reporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: "[\(validScreenshotAnalysisJSON())]"))
        ]

        let result = try await OpenRouterClient(
            session: makeSession(), eventReporter: reporter
        ).analyzeChatScreenshot(makeRequest(), apiKey: "key", model: .qwen37Plus)

        XCTAssertEqual(result.messages.map(\.text), ["Hello"])
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertTrue(hasValidationCategory("recovered", in: reporter.events))
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
            makeRequest(), apiKey: "key", model: .qwen37Plus
        )

        AnalysisURLProtocolStub.reset()
        var invalid = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(validScreenshotAnalysisJSON().utf8))
                as? [String: Any]
        )
        invalid["extra"] = true
        AnalysisURLProtocolStub.responses = [
            (200, openRouterResponse(content: jsonString(invalid)))
        ]

        await assertThrowsErrorAsync {
            _ = try await OpenRouterClient(session: self.makeSession()).analyzeChatScreenshot(
                self.makeRequest(), apiKey: "key", model: .qwen37Plus
            )
        }
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
    }

    @MainActor
    func testOpenAIUsesOneStandardRequestForRecoveredOrFatalOutput() async throws {
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
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: reporter.events), [1])
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
            }
        )
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
    }

    @MainActor
    func testOpenAIImportUsesOneRequestForRecoveredAndFatalOutput() async throws {
        let recoveredReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, openAIResponse(content: #"{"messages":[{"text":"Hello"}]}"#))
        ]
        let recovered = try await OpenAIClient(
            session: makeSession(), eventReporter: recoveredReporter
        ).analyzeChatScreenshot(makeRequest(), apiKey: "key", model: .gpt56Sol)

        XCTAssertEqual(recovered.messages.first?.text, "Hello")
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
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
                    self.makeRequest(), apiKey: "key", model: .gpt56Sol
                )
            },
            errorHandler: {
                self.assertStructuredOutputError(
                    $0, provider: "openai", codingPath: "messages[0].text"
                )
            }
        )
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
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
            ).analyzeChatScreenshot(makeRequest(), apiKey: "key", model: .miniMaxM3)

            XCTAssertEqual(result.messages.first?.text, "Hello")
            let request = try XCTUnwrap(AnalysisURLProtocolStub.requests.first)
            XCTAssertEqual(request.url?.host, host)
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try jsonBody(request)
            XCTAssertEqual(body["model"] as? String, "MiniMax-M3")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 4_000)
            XCTAssertNil(body["response_format"])
            XCTAssertTrue(
                reporter.events.contains { event in
                    guard
                        case .providerResponse(
                            _, let eventProvider, "MiniMax-M3", 1, _, 200, "req-test", "stop",
                            _, 100, 20, 60
                        ) = event
                    else { return false }
                    return eventProvider == provider
                }
            )
        }
    }

    @MainActor
    func testMiniMaxTranscriptAndRepliesUseTextContentAndTaskTokenCaps() async throws {
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: #"{"messages":[{"text":"你好"}]}"#))
        ]
        _ = try await MiniMaxClient(region: .china, session: makeSession())
            .analyzeChatScreenshot(
                ChatImportAnalysisRequest(
                    transcriptItems: ["Alice: 你好"], candidates: []
                ),
                apiKey: "key",
                model: .miniMaxM3
            )
        let transcriptBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        let transcriptMessages = try XCTUnwrap(transcriptBody["messages"] as? [[String: Any]])
        XCTAssertTrue(transcriptMessages[1]["content"] is String)

        AnalysisURLProtocolStub.reset()
        AnalysisURLProtocolStub.responses = [(200, miniMaxResponse(content: validDraftingJSON()))]
        let replies = try await MiniMaxClient(region: .international, session: makeSession())
            .generateSuggestedReplies(
                makeReplyRequest(task: .drafting), apiKey: "key", model: .miniMaxM3
            )

        XCTAssertEqual(replies.replies, ["First", "Second"])
        let replyBody = try jsonBody(try XCTUnwrap(AnalysisURLProtocolStub.requests.first))
        XCTAssertEqual(replyBody["max_completion_tokens"] as? Int, 3_200)
        XCTAssertNil(replyBody["response_format"])
        let replyMessages = try XCTUnwrap(replyBody["messages"] as? [[String: Any]])
        XCTAssertTrue(replyMessages.allSatisfy { $0["content"] is String })
    }

    @MainActor
    func testMiniMaxUsesOneRequestForRecoveredAndFatalReplies() async throws {
        let recoveredReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: "Result:\n\(validStandardRepliesJSON())"))
        ]
        let recovered = try await MiniMaxClient(
            region: .international,
            session: makeSession(),
            eventReporter: recoveredReporter
        ).generateSuggestedReplies(
            makeReplyRequest(task: .standard), apiKey: "key", model: .miniMaxM3
        )

        XCTAssertEqual(recovered.replies, ["First", "Second"])
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertTrue(hasValidationCategory("recovered", in: recoveredReporter.events))

        AnalysisURLProtocolStub.reset()
        let fatalReporter = SpyImportEventReporter()
        AnalysisURLProtocolStub.responses = [
            (200, miniMaxResponse(content: "{}")),
            (200, miniMaxResponse(content: validStandardRepliesJSON()))
        ]
        await assertThrowsErrorAsync(
            {
                _ = try await MiniMaxClient(
                    region: .international,
                    session: self.makeSession(),
                    eventReporter: fatalReporter
                ).generateSuggestedReplies(
                    self.makeReplyRequest(task: .standard),
                    apiKey: "key",
                    model: .miniMaxM3
                )
            },
            errorHandler: {
                self.assertStructuredOutputError(
                    $0, provider: "miniMaxInternational", codingPath: "root"
                )
            }
        )
        XCTAssertEqual(AnalysisURLProtocolStub.requests.count, 1)
        XCTAssertEqual(providerAttempts(in: fatalReporter.events), [1])
    }
}
