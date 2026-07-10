import SwiftData
import XCTest

@testable import zeptly

final class SuggestedRepliesCoordinatorTests: XCTestCase {
    @MainActor
    func testOneUseDraftCachesRepliesForSubsequentAppLoad() async throws {
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
        XCTAssertEqual(
            service.requests[0].draftingInput, "Tell her Friday works, but make it warmer.")
        XCTAssertTrue(
            SuggestedReplyPrompt.input(for: service.requests[0]).contains("Tell her Friday works"))

        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.replies, result.replies)
        XCTAssertEqual(cache.conversationStrategy, result.conversationStrategy)
        XCTAssertEqual(cache.strategyRationale, result.strategyRationale)
        XCTAssertEqual(cache.historySummary, "")
        XCTAssertEqual(cache.summarizedMessageCount, 0)
        XCTAssertEqual(cache.summarizedPrefixFingerprint, "")

        let appLoad = try XCTUnwrap(coordinator.cachedReplies(chatID: chatID))
        XCTAssertEqual(appLoad.source, .cached)
        XCTAssertEqual(appLoad.replies, result.replies)
        XCTAssertEqual(appLoad.conversationStrategy, result.conversationStrategy)
        XCTAssertEqual(appLoad.strategyRationale, result.strategyRationale)
        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testCacheOnlyLoadDoesNotGenerateWhenCacheIsMissingOrStale() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "cache-only-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()
        let service = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)
        let viewModel = SuggestedRepliesViewModel(chatID: chatID, coordinator: coordinator)

        viewModel.loadCached()
        XCTAssertTrue(viewModel.replies.isEmpty)
        XCTAssertEqual(service.requests.count, 0)

        _ = try await coordinator.generate(chatID: chatID, draftingInput: "Use this")
        viewModel.loadCached()
        XCTAssertEqual(viewModel.replies.map(\.text), ["Reply 1A", "Reply 1B"])
        XCTAssertEqual(viewModel.conversationStrategy, "Strategy 1")
        XCTAssertEqual(viewModel.strategyRationale, "Rationale 1")
        XCTAssertEqual(service.requests.count, 1)

        container.mainContext.insert(makeMessage(chatID: chatID, index: 1))
        try container.mainContext.save()
        viewModel.loadCached()
        XCTAssertTrue(viewModel.replies.isEmpty)
        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testOneUseDraftPreservesExistingSummaryAndDoesNotApplyAnalysisOutput() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let defaultPersonaID = try PersonaRepository(container: container).defaultPersonaID()
        let chatID = "drafting-input-existing-cache-chat"
        let message = makeMessage(chatID: chatID, index: 0)
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(message)
        container.mainContext.insert(
            SuggestedReplyCacheRecord(
                chatID: chatID,
                historySummary: "Existing summary",
                summarizedMessageCount: 7,
                summarizedPrefixFingerprint: "existing-prefix",
                repliesJSON: "[\"Old A\",\"Old B\"]",
                conversationStrategy: "Previous strategy",
                strategyRationale: "Previous rationale",
                inputFingerprint: "old-fingerprint",
                provider: ProviderPlatform.zaiInternational.rawValue,
                model: ProviderModel.glm47FlashX.rawValue,
                promptVersion: SuggestedReplyPrompt.version
            )
        )
        try container.mainContext.save()

        let service = StubReplyService { _ in
            SuggestedReplyGenerationResult(
                historySummary: "Draft-generated summary must be ignored",
                replies: ["Draft A", "Draft B"],
                conversationStrategy: "Draft strategy",
                strategyRationale: "Draft rationale",
                memoryChanges: [
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Must not be saved",
                        sourceMessageIDs: [message.id]
                    )
                ],
                personaObservationChanges: []
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        _ = try await coordinator.generate(chatID: chatID, draftingInput: "Use this once")

        XCTAssertEqual(service.requests.first?.draftingInput, "Use this once")
        XCTAssertEqual(service.requests.first?.previousConversationStrategy, "Previous strategy")
        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.replies, ["Draft A", "Draft B"])
        XCTAssertEqual(cache.conversationStrategy, "Draft strategy")
        XCTAssertEqual(cache.strategyRationale, "Draft rationale")
        XCTAssertEqual(cache.historySummary, "Existing summary")
        XCTAssertEqual(cache.summarizedMessageCount, 7)
        XCTAssertEqual(cache.summarizedPrefixFingerprint, "existing-prefix")
        XCTAssertTrue(try repository.contactMemories(chatID: chatID).isEmpty)
        XCTAssertFalse(
            try repository.personaLearningMessages(
                chatID: chatID,
                personaID: defaultPersonaID,
                assignedAt: .distantPast
            ).isEmpty
        )
        XCTAssertFalse(
            try repository.personaObservations(personaID: defaultPersonaID).contains {
                $0.origin == PersonaObservationOrigin.ai.rawValue
            })
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
            value: ContactMemory(text: "Likes tea")
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
        let personas = PersonaRepository(container: container)
        let thoughtfulID = try XCTUnwrap(try personas.personas().first { $0.name == "Thoughtful" })
            .id
        let chatID = "reply-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(
            ContactContextRecord(
                chatID: chatID,
                currentInteractionGoal: "Confirm dinner",
                personaID: thoughtfulID
            )
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: chatID,
                value: ContactMemory(text: "Met at university")
            )
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: chatID,
                value: ContactMemory(text: "Vegetarian")
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
        XCTAssertEqual(
            client.requests[0].contactMemories.map(\.text), ["Met at university", "Vegetarian"])
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
        XCTAssertEqual(client.requests[1].previousConversationStrategy, "Strategy 1")

        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.summarizedMessageCount, 3)
        XCTAssertEqual(cache.historySummary, "Summary through Message 2")
        XCTAssertEqual(cache.replies.count, 2)
        XCTAssertEqual(cache.conversationStrategy, "Strategy 2")
        XCTAssertEqual(cache.strategyRationale, "Rationale 2")
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
                replies: ["First", "Second"],
                conversationStrategy: "Stay aligned with the newest message.",
                strategyRationale: "The transcript changed during generation in this test."
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
                conversationStrategy: "Answer the partner-hotel question without adding unsupported details.",
                strategyRationale: "Only contact-authored messages can support durable contact memory.",
                memoryChanges: [
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Asked about partner hotels in Beijing",
                        sourceMessageIDs: [contactMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "No partner hotels in Beijing",
                        sourceMessageIDs: [userMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Other participant detail",
                        sourceMessageIDs: [otherMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Unknown sender detail",
                        sourceMessageIDs: [unknownMessage.id]
                    ),
                    ContactMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Mixed sender detail",
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
            preview: "Preview",
            chipTitle: "General",
            chipSymbol: "number",
            avatarSymbol: nil,
            initials: "S",
            appearanceStyle: 0,
            isUnread: false
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
            replies: ["Reply \(requests.count)A", "Reply \(requests.count)B"],
            conversationStrategy: "Strategy \(requests.count)",
            strategyRationale: "Rationale \(requests.count)"
        )
    }
}

extension AIProviderExecutionContext {
    fileprivate static var zaiDefaultReplies: AIProviderExecutionContext {
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

    fileprivate static var zhipuDefaultReplies: AIProviderExecutionContext {
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
