import SwiftData
import XCTest

@testable import zeptly

final class SuggestedRepliesCoordinatorTests: XCTestCase {
    @MainActor
    func testOneUseDraftBypassesGenericReplyCache() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "drafting-input-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()
        let service = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        let result = try await coordinator.generate(
            chatID: chatID,
            draftingInput: "  Tell her Friday works, but make it warmer.  "
        )

        XCTAssertEqual(result.source, .generated)
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests[0].draftingInput, "Tell her Friday works, but make it warmer.")
        XCTAssertNil(try repository.suggestedReplyCache(chatID: chatID))
        XCTAssertTrue(SuggestedReplyPrompt.input(for: service.requests[0]).contains("Tell her Friday works"))
    }

    @MainActor
    func testChangingActiveMemoryInvalidatesCachedRepliesWhileArchivedMemoryDoesNot() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "memory-cache-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        let active = ContactMemoryRecord(
            chatID: chatID,
            value: ContactMemory(text: "Likes tea", kind: .preference)
        )
        let archived = ContactMemoryRecord(
            chatID: chatID,
            value: ContactMemory(text: "Old office", status: .archived)
        )
        container.mainContext.insert(active)
        container.mainContext.insert(archived)
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 1)

        archived.text = "Older office"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 1)

        active.text = "Likes coffee"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests.last?.contactMemories.map(\.text), ["Likes coffee"])
    }

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
                currentInteractionGoal: "Confirm dinner",
                preferredPersona: "Warm & Collaborative"
            )
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: chatID,
                value: ContactMemory(text: "Met at university", kind: .relationship)
            )
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: chatID,
                value: ContactMemory(text: "Vegetarian", kind: .preference)
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
        XCTAssertEqual(client.requests[0].contactMemories.map(\.text), ["Met at university", "Vegetarian"])
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
    func testPersistsReconciledMemoriesAndCachesAgainstPostUpdateState() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "memory-maintenance-chat"
        let message = makeMessage(chatID: chatID, index: 1)
        let userMemory = ContactMemory(text: "Lives in Paris", kind: .fact)
        let aiMemory = ContactMemory(
            text: "Conference next week",
            kind: .event,
            origin: .ai,
            certainty: .aiInferred
        )
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(message)
        container.mainContext.insert(ContactMemoryRecord(chatID: chatID, value: userMemory))
        container.mainContext.insert(ContactMemoryRecord(chatID: chatID, value: aiMemory))
        try container.mainContext.save()

        let client = StubReplyService { request in
            SuggestedReplyGenerationResult(
                historySummary: request.existingHistorySummary,
                replies: ["First", "Second"],
                memoryChanges: [
                    ContactMemoryChange(
                        action: .update,
                        targetMemoryID: userMemory.id,
                        text: "Now lives in Berlin",
                        kind: .fact,
                        sourceMessageIDs: [message.id]
                    ),
                    ContactMemoryChange(
                        action: .archive,
                        targetMemoryID: aiMemory.id,
                        text: nil,
                        kind: nil,
                        sourceMessageIDs: [message.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Vegetarian",
                        kind: .preference,
                        sourceMessageIDs: [message.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Unsupported detail",
                        kind: .fact,
                        sourceMessageIDs: [UUID()]
                    )
                ]
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)

        _ = try await coordinator.generate(chatID: chatID)
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(client.requests.count, 1)
        let memories = try repository.contactContextValue(chatID: chatID).contactMemories
        XCTAssertEqual(memories.first { $0.id == userMemory.id }?.status, .superseded)
        XCTAssertEqual(memories.first { $0.id == aiMemory.id }?.status, .archived)
        XCTAssertEqual(memories.first { $0.text == "Now lives in Berlin" }?.origin, .ai)
        XCTAssertEqual(memories.first { $0.text == "Vegetarian" }?.sourceMessageIDs, [message.id])
        XCTAssertNil(memories.first { $0.text == "Unsupported detail" })
    }

    @MainActor
    func testPersistsOnlyMemorySupportedExclusivelyByContactMessages() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "contact-owned-memory-chat"
        let userMessage = makeMessage(chatID: chatID, index: 0)
        let contactMessage = makeMessage(chatID: chatID, index: 1)
        let otherMessage = makeMessage(chatID: chatID, index: 2)
        otherMessage.senderKind = "other"
        otherMessage.senderName = "Alex"
        let unknownMessage = makeMessage(chatID: chatID, index: 3)
        unknownMessage.senderKind = "unknown"
        unknownMessage.senderName = nil

        container.mainContext.insert(makeChat(id: chatID))
        for message in [userMessage, contactMessage, otherMessage, unknownMessage] {
            container.mainContext.insert(message)
        }
        try container.mainContext.save()

        let client = StubReplyService { request in
            XCTAssertEqual(
                request.recentMessages.map(\.sender),
                ["user", "contact", "other", "unknown"]
            )
            return SuggestedReplyGenerationResult(
                historySummary: request.existingHistorySummary,
                replies: ["First", "Second"],
                memoryChanges: [
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Asked about partner hotels in Beijing",
                        kind: .fact,
                        sourceMessageIDs: [contactMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "No partner hotels in Beijing",
                        kind: .fact,
                        sourceMessageIDs: [userMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Other participant detail",
                        kind: .fact,
                        sourceMessageIDs: [otherMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Unknown sender detail",
                        kind: .fact,
                        sourceMessageIDs: [unknownMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Mixed sender detail",
                        kind: .fact,
                        sourceMessageIDs: [contactMessage.id, userMessage.id]
                    )
                ]
            )
        }

        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)

        let activeMemories = try repository.contactContextValue(chatID: chatID).contactMemories
            .filter { $0.status == .active }
        XCTAssertEqual(activeMemories.map(\.text), ["Asked about partner hotels in Beijing"])
        XCTAssertEqual(activeMemories.first?.sourceMessageIDs, [contactMessage.id])
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
