import SwiftData
import XCTest

@testable import zeptly

final class SuggestedRepliesCoordinatorTests: XCTestCase {
    @MainActor
    func testCachesRepliesAndIncrementallySummarizesMessagesBeyondRecentTwenty() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "reply-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(
            ContactContextRecord(
                chatID: chatID,
                relationshipSubtitle: "Friend",
                relationshipNotes: "Met at university",
                keyFactsJSON: "[\"Vegetarian\"]",
                currentInteractionGoal: "Confirm dinner",
                preferredPersona: "Warm & Collaborative"
            )
        )
        for index in 0..<22 {
            container.mainContext.insert(makeMessage(chatID: chatID, index: index))
        }
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(
            aiService: client,
            repository: repository
        )

        let first = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(first.source, .generated)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].summaryMode, .rebuild)
        XCTAssertEqual(client.requests[0].olderMessagesToSummarize.count, 2)
        XCTAssertEqual(client.requests[0].recentMessages.count, 20)
        XCTAssertEqual(client.models, [.glm47FlashX])

        let cached = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(cached.source, .cached)
        XCTAssertEqual(client.requests.count, 1)

        container.mainContext.insert(makeMessage(chatID: chatID, index: 22))
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[1].summaryMode, .incremental)
        XCTAssertEqual(client.requests[1].olderMessagesToSummarize.map(\.text), ["Message 2"])
        XCTAssertEqual(client.requests[1].existingHistorySummary, "Summary through Message 1")

        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.summarizedMessageCount, 3)
        XCTAssertEqual(cache.historySummary, "Summary through Message 2")
        XCTAssertEqual(cache.replies.count, 2)
    }

    @MainActor
    func testChangingSummarizedPrefixForcesSummaryRebuild() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "mutated-chat"
        container.mainContext.insert(makeChat(id: chatID))
        for index in 0..<21 {
            container.mainContext.insert(makeMessage(chatID: chatID, index: index))
        }
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(
            aiService: client,
            repository: repository
        )
        _ = try await coordinator.generate(chatID: chatID)

        let first = try XCTUnwrap(repository.messages(chatID: chatID).first)
        first.senderKind = "unknown"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[1].summaryMode, .rebuild)
        XCTAssertEqual(client.requests[1].olderMessagesToSummarize.first?.sender, "unknown")
    }

    @MainActor
    func testDoesNotPersistRepliesWhenGroundingChangesDuringRequest() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "racing-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()

        let client = StubReplyService { request in
            container.mainContext.insert(self.makeMessage(chatID: chatID, index: 1))
            try! container.mainContext.save()
            return SuggestedReplyGenerationResult(
                historySummary: request.existingHistorySummary,
                replies: ["First", "Second"]
            )
        }
        let coordinator = SuggestedRepliesCoordinator(
            aiService: client,
            repository: repository
        )

        do {
            _ = try await coordinator.generate(chatID: chatID)
            XCTFail("Expected stale generation to be cancelled")
        } catch is CancellationError {
            // Expected: the transcript changed before the provider result could be committed.
        }
        XCTAssertNil(try repository.suggestedReplyCache(chatID: chatID))
    }

    @MainActor
    func testMapsStructuredProviderFailureToReplySpecificError() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "schema-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()

        let client = StubReplyService { request in
            throw ProviderConnectionError.structuredOutput(
                ProviderStructuredOutputError(
                    provider: "test",
                    traceID: request.traceID,
                    failure: StructuredOutputFailure(kind: .schemaMismatch, codingPath: "replies")
                )
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)

        do {
            _ = try await coordinator.generate(chatID: chatID)
            XCTFail("Expected a reply-specific schema error")
        } catch let error as SuggestedRepliesError {
            XCTAssertEqual(error.code, "reply_schema_mismatch")
            XCTAssertTrue(error.localizedDescription.contains("generate replies"))
        }
    }

    @MainActor
    func testSwitchingProviderInvalidatesReplyCacheWithoutChangingCoordinator() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "provider-switch-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()

        let service = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(
            (try repository.suggestedReplyCache(chatID: chatID))?.provider,
            ProviderPlatform.zaiInternational.rawValue
        )

        service.context = .zhipuDefaultReplies
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(service.requests.count, 2)
        XCTAssertEqual(
            (try repository.suggestedReplyCache(chatID: chatID))?.provider,
            ProviderPlatform.zhipuChina.rawValue
        )
        XCTAssertEqual(service.models, [.glm47FlashX, .glm47FlashX])
    }

    @MainActor
    private func makeChat(id: String) -> ChatRecord {
        ChatRecord(
            id: id,
            name: "Sarah",
            lastActivityLabel: "Now",
            preview: "Preview",
            chipTitle: "General",
            chipSymbol: "number",
            avatarSymbol: nil,
            initials: "S",
            appearanceStyle: 0,
            isUnread: false,
            isOnline: false
        )
    }

    @MainActor
    private func makeMessage(chatID: String, index: Int) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID,
            senderKind: index.isMultiple(of: 2) ? "user" : "contact",
            senderName: index.isMultiple(of: 2) ? nil : "Sarah",
            text: "Message \(index)",
            normalizedText: "message \(index)",
            timeLabel: "",
            sortIndex: index
        )
    }
}

@MainActor
private final class StubReplyService: AIServiceProviding {
    typealias Handler = (SuggestedReplyGenerationRequest) throws -> SuggestedReplyGenerationResult

    private(set) var requests: [SuggestedReplyGenerationRequest] = []
    private(set) var models: [ProviderModel] = []
    var context: AIProviderExecutionContext
    private let handler: Handler?

    init(
        context: AIProviderExecutionContext = .zaiDefaultReplies,
        handler: Handler? = nil
    ) {
        self.context = context
        self.handler = handler
    }

    func activeContext(
        requiring capability: AIProviderCapability
    ) throws -> AIProviderExecutionContext {
        guard capability == context.capability else {
            throw AIServiceError.unsupportedCapability
        }
        return context
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis {
        throw AIServiceError.unsupportedCapability
    }

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        using context: AIProviderExecutionContext
    ) async throws -> SuggestedReplyGenerationResult {
        requests.append(request)
        models.append(context.effectiveModel)
        if let handler {
            return try handler(request)
        }
        let summary: String
        if let last = request.olderMessagesToSummarize.last {
            summary = "Summary through \(last.text)"
        } else {
            summary = request.existingHistorySummary
        }
        return SuggestedReplyGenerationResult(
            historySummary: summary,
            replies: ["Reply \(requests.count)A", "Reply \(requests.count)B"]
        )
    }
}

private extension AIProviderExecutionContext {
    static var zaiDefaultReplies: AIProviderExecutionContext {
        AIProviderExecutionContext(
            platform: .zaiInternational,
            profile: ProviderModelProfile(
                selectedModel: .glm46VFlashX,
                screenshotAnalysisModel: .glm46VFlashX,
                suggestedReplyModel: .glm47FlashX
            ),
            capability: .suggestedReplies,
            effectiveModel: .glm47FlashX
        )
    }

    static var zhipuDefaultReplies: AIProviderExecutionContext {
        AIProviderExecutionContext(
            platform: .zhipuChina,
            profile: ProviderModelProfile(
                selectedModel: .glm46VFlashX,
                screenshotAnalysisModel: .glm46VFlashX,
                suggestedReplyModel: .glm47FlashX
            ),
            capability: .suggestedReplies,
            effectiveModel: .glm47FlashX
        )
    }
}
