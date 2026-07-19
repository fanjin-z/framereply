import SwiftData
import XCTest

@testable import FrameReply

final class SuggestedRepliesCoordinatorTests: XCTestCase {
    @MainActor
    func testOneUseDraftCachesRepliesWithoutApplyingAnalysisOutput() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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
                    ChatMemoryChange(
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

        let result = try await coordinator.generate(
            chatID: chatID,
            draftingInput: "  Use this once  "
        )

        XCTAssertEqual(service.requests.first?.draftingInput, "Use this once")
        XCTAssertEqual(service.requests.first?.previousConversationStrategy, "Previous strategy")
        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.replies, ["Draft A", "Draft B"])
        XCTAssertEqual(cache.conversationStrategy, "Draft strategy")
        XCTAssertEqual(cache.strategyRationale, "Draft rationale")
        XCTAssertEqual(cache.historySummary, "Existing summary")
        XCTAssertEqual(cache.summarizedMessageCount, 7)
        XCTAssertEqual(cache.summarizedPrefixFingerprint, "existing-prefix")
        XCTAssertTrue(try repository.chatMemories(chatID: chatID).isEmpty)
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
        let cached = try XCTUnwrap(coordinator.cachedReplies(chatID: chatID))
        XCTAssertEqual(cached.source, .cached)
        XCTAssertEqual(cached.replies, result.replies)
        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testCacheValidityTracksMessagesActiveMemoryAndProvider() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "memory-cache-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        let active = ChatMemoryRecord(
            chatID: chatID,
            value: ChatMemory(text: "Likes tea")
        )
        let archived = ChatMemoryRecord(
            chatID: chatID,
            value: ChatMemory(text: "Old office", status: .archived)
        )
        container.mainContext.insert(active)
        container.mainContext.insert(archived)
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        XCTAssertNil(try coordinator.cachedReplies(chatID: chatID))
        XCTAssertEqual(client.requests.count, 0)

        _ = try await coordinator.generate(chatID: chatID)
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(try coordinator.cachedReplies(chatID: chatID)?.source, .cached)

        archived.text = "Older office"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 1)

        active.text = "Likes coffee"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests.last?.chatMemories.map(\.text), ["Likes coffee"])

        container.mainContext.insert(makeMessage(chatID: chatID, index: 1))
        try container.mainContext.save()
        XCTAssertNil(try coordinator.cachedReplies(chatID: chatID))
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 3)

        client.context = .zhipuDefaultReplies
        _ = try await coordinator.generate(chatID: chatID)
        XCTAssertEqual(client.requests.count, 4)
    }

    @MainActor
    func testCachesRepliesAndIncrementallySummarizesMessagesBeyondRecentTwenty() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let personas = PersonaRepository(container: container)
        let thoughtfulID = try XCTUnwrap(try personas.personas().first { $0.name == "Thoughtful" })
            .id
        let chatID = "reply-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(
            ChatContextRecord(
                chatID: chatID,
                currentInteractionGoal: "Confirm dinner",
                personaID: thoughtfulID
            )
        )
        container.mainContext.insert(
            ChatMemoryRecord(
                chatID: chatID,
                value: ChatMemory(text: "Met at university")
            )
        )
        container.mainContext.insert(
            ChatMemoryRecord(
                chatID: chatID,
                value: ChatMemory(text: "Vegetarian")
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
            client.requests[0].chatMemories.map(\.text), ["Met at university", "Vegetarian"])
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
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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
    func testPersistsOnlyMemorySupportedExclusivelyByOtherParticipantMessages() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "other-participant-owned-memory-chat"
        let userMessage = makeMessage(chatID: chatID, index: 0)
        let otherParticipantMessage = makeMessage(chatID: chatID, index: 1)
        let otherMessage = makeMessage(chatID: chatID, index: 2)
        otherMessage.senderKind = "group_participant"
        otherMessage.senderName = "Alex"
        let unknownMessage = makeMessage(chatID: chatID, index: 3)
        unknownMessage.senderKind = "unknown"
        unknownMessage.senderName = nil

        container.mainContext.insert(makeChat(id: chatID))
        for message in [userMessage, otherParticipantMessage, otherMessage, unknownMessage] {
            container.mainContext.insert(message)
        }
        try container.mainContext.save()

        let client = StubReplyService { request in
            XCTAssertEqual(
                request.recentMessages.map(\.sender),
                ["user", "other_participant", "group_participant", "unknown"]
            )
            return SuggestedReplyGenerationResult(
                historySummary: request.existingHistorySummary,
                replies: ["First", "Second"],
                conversationStrategy:
                    "Answer the partner-hotel question without adding unsupported details.",
                strategyRationale:
                    "Only other-participant-authored messages can support durable chat memory.",
                memoryChanges: [
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Asked about partner hotels in Beijing",
                        sourceMessageIDs: [otherParticipantMessage.id]
                    ),
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "No partner hotels in Beijing",
                        sourceMessageIDs: [userMessage.id]
                    ),
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Other participant detail",
                        sourceMessageIDs: [otherMessage.id]
                    ),
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Unknown sender detail",
                        sourceMessageIDs: [unknownMessage.id]
                    ),
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Mixed sender detail",
                        sourceMessageIDs: [otherParticipantMessage.id, userMessage.id]
                    )
                ]
            )
        }

        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)

        let activeMemories = try repository.chatContextValue(chatID: chatID).chatMemories
            .filter { $0.status == .active }
        XCTAssertEqual(activeMemories.map(\.text), ["Asked about partner hotels in Beijing"])
        XCTAssertEqual(activeMemories.first?.origin, .ai)
    }

    @MainActor
    private func makeChat(id: String) -> ChatRecord {
        ChatRecord(
            id: id,
            name: "Sarah",
            preview: "Preview"
        )
    }

    @MainActor
    private func makeMessage(chatID: String, index: Int) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID,
            senderKind: index.isMultiple(of: 2) ? "user" : "other_participant",
            senderName: index.isMultiple(of: 2) ? nil : "Sarah",
            text: "Message \(index)",
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
        context: AIProviderExecutionContext? = nil,
        handler: Handler? = nil
    ) {
        self.context = context ?? .zaiDefaultReplies
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
            capability: .suggestedReplies,
            effectiveModel: .glm47FlashX
        )
    }

    fileprivate static var zhipuDefaultReplies: AIProviderExecutionContext {
        AIProviderExecutionContext(
            platform: .zhipuChina,
            capability: .suggestedReplies,
            effectiveModel: .glm47FlashX
        )
    }
}
