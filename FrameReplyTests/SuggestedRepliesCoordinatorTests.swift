import SwiftData
import XCTest

@testable import FrameReply

final class SuggestedRepliesCoordinatorTests: XCTestCase {
    @MainActor
    func testProvisionalIdentityGroundsRepliesWithoutDurableLearning() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let priorChatID = "chat-gamma"
        let provisionalChatID = "chat-delta"
        container.mainContext.insert(
            ChatRecord(
                id: priorChatID,
                title: "Chat Gamma",
                previewText: "Synthetic message A",
                conversationKind: .direct
            )
        )
        try container.mainContext.save()
        try repository.addSelfAlias(
            displayLabel: "Alias Alpha",
            chatID: priorChatID
        )

        let selfMessage = ChatMessageRecord(
            chatID: provisionalChatID,
            senderKind: "unknown",
            senderName: "Alias Alpha",
            text: "Synthetic message A",
            timeLabel: "",
            sortIndex: 0
        )
        let counterpartMessage = ChatMessageRecord(
            chatID: provisionalChatID,
            senderKind: "unknown",
            senderName: "Contact Beta",
            text: "Synthetic message B",
            timeLabel: "",
            sortIndex: 1
        )
        container.mainContext.insert(
            ChatRecord(
                id: provisionalChatID,
                title: nil,
                previewText: "Synthetic message B",
                conversationKind: .direct,
                isProvisional: true
            )
        )
        container.mainContext.insert(selfMessage)
        container.mainContext.insert(counterpartMessage)
        try container.mainContext.save()

        let client = StubReplyService { request in
            XCTAssertEqual(
                request.recentMessages.map(\.sender),
                ["user", "other_participant"]
            )
            XCTAssertNil(request.recentMessages[0].senderName)
            XCTAssertEqual(request.recentMessages[1].senderName, "Contact Beta")
            return SuggestedReplyGenerationResult(
                historySummary: "Synthetic summary A",
                replies: ["Synthetic reply A", "Synthetic reply B"],
                conversationStrategy: "Synthetic strategy A",
                strategyRationale: "Synthetic rationale A",
                memoryChanges: [
                    ChatMemoryChange(
                        action: .add,
                        targetMemoryID: nil,
                        text: "Synthetic memory A",
                        sourceMessageIDs: [counterpartMessage.id]
                    )
                ]
            )
        }
        let coordinator = SuggestedRepliesCoordinator(
            aiService: client,
            repository: repository
        )

        _ = try await coordinator.generate(chatID: provisionalChatID)

        XCTAssertEqual(
            try repository.messages(chatID: provisionalChatID).map(\.senderKind),
            ["unknown", "unknown"]
        )
        XCTAssertTrue(try repository.chatMemories(chatID: provisionalChatID).isEmpty)
        let cache = try XCTUnwrap(
            repository.suggestedReplyCache(chatID: provisionalChatID)
        )
        XCTAssertEqual(cache.replies, ["Synthetic reply A", "Synthetic reply B"])
        XCTAssertEqual(cache.historySummary, "")
        XCTAssertEqual(cache.summarizedMessageCount, 0)
        XCTAssertEqual(
            try coordinator.cachedReplies(chatID: provisionalChatID)?.source,
            .cached
        )
        XCTAssertTrue(
            try container.mainContext.fetch(
                FetchDescriptor<PersonaLearningReceiptRecord>(
                    predicate: #Predicate { $0.chatID == provisionalChatID }
                )
            ).isEmpty
        )
    }

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
                appLanguage: "en",
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
        XCTAssertNil(service.requests.first?.previousConversationStrategy)
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
    func testCompletedOutgoingTurnStoresLocalWaitGuidanceAndNoReplies() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "synthetic-outgoing-wait-chat"
        let outgoing = makeMessage(chatID: chatID, index: 0)
        outgoing.text = "Could you share an update?"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(outgoing)
        try container.mainContext.save()

        let service = StubReplyService { _ in
            SuggestedReplyGenerationResult(
                historySummary: nil,
                replies: [],
                conversationStrategy:
                    "After a response, acknowledge the update and continue with one relevant question.",
                strategyRationale:
                    "The future response determines which part of the topic needs attention."
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        let outcome = try await coordinator.generate(chatID: chatID)

        XCTAssertTrue(outcome.replies.isEmpty)
        XCTAssertEqual(
            outcome.conversationStrategy,
            "Wait for a response first. After a response, acknowledge the update and continue with one relevant question."
        )
        XCTAssertEqual(
            outcome.strategyRationale,
            "You sent the latest message, so another message now may be premature. The future response determines which part of the topic needs attention."
        )
        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertTrue(cache.replies.isEmpty)
        XCTAssertEqual(cache.conversationStrategy, outcome.conversationStrategy)
        XCTAssertEqual(cache.strategyRationale, outcome.strategyRationale)
        XCTAssertEqual(
            try coordinator.cachedReplies(chatID: chatID)?.conversationStrategy,
            outcome.conversationStrategy
        )
    }

    @MainActor
    func testIncompleteOutgoingTurnKeepsTwoUserAuthoredFollowUps() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "synthetic-outgoing-follow-up-chat"
        let outgoing = makeMessage(chatID: chatID, index: 0)
        outgoing.text = "One more detail:"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(outgoing)
        try container.mainContext.save()

        let service = StubReplyService { request in
            XCTAssertEqual(request.recentMessages.last?.sender, "user")
            return SuggestedReplyGenerationResult(
                historySummary: nil,
                replies: ["The first detail.", "The same detail, phrased differently."],
                conversationStrategy: "Finish the point, then leave room for a response.",
                strategyRationale: "The trailing message clearly introduces missing content."
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        let outcome = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(
            outcome.replies,
            ["The first detail.", "The same detail, phrased differently."]
        )
        XCTAssertEqual(
            outcome.conversationStrategy,
            "Finish the point, then leave room for a response."
        )
        XCTAssertEqual(
            outcome.strategyRationale,
            "The trailing message clearly introduces missing content."
        )
        XCTAssertEqual(
            try repository.suggestedReplyCache(chatID: chatID)?.replies,
            outcome.replies
        )
    }

    @MainActor
    func testIncomingDirectAndGroupTurnsAcceptExactlyTwoUserReplies() async throws {
        let cases: [(ChatConversationKind, String, String)] = [
            (.direct, "other_participant", "synthetic-direct-incoming-chat"),
            (.group, "group_participant", "synthetic-group-incoming-chat")
        ]

        for (conversationKind, senderKind, chatID) in cases {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
            let repository = ChatRepository(container: container)
            let chat = ChatRecord(
                id: chatID,
                title: "Contact",
                previewText: "Synthetic incoming message",
                conversationKind: conversationKind
            )
            let incoming = ChatMessageRecord(
                chatID: chatID,
                senderKind: senderKind,
                senderName: "Contact",
                text: "Can you confirm the plan?",
                timeLabel: "",
                sortIndex: 0
            )
            container.mainContext.insert(chat)
            container.mainContext.insert(incoming)
            try container.mainContext.save()

            let service = StubReplyService { request in
                XCTAssertEqual(request.recentMessages.last?.sender, senderKind)
                return SuggestedReplyGenerationResult(
                    historySummary: nil,
                    replies: ["Yes, that works.", "That plan works for me."],
                    conversationStrategy: "Confirm the plan and keep the next step specific.",
                    strategyRationale: "The latest incoming turn asks for confirmation."
                )
            }
            let coordinator = SuggestedRepliesCoordinator(
                aiService: service,
                repository: repository
            )

            let outcome = try await coordinator.generate(chatID: chatID)

            XCTAssertEqual(outcome.replies, ["Yes, that works.", "That plan works for me."])
            XCTAssertEqual(service.requests.count, 1)
        }
    }

    @MainActor
    func testIncomingTurnRejectsSuccessfulEmptyReplyResult() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "synthetic-incoming-empty-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 1))
        try container.mainContext.save()

        let service = StubReplyService { _ in
            SuggestedReplyGenerationResult(
                historySummary: nil,
                replies: [],
                conversationStrategy: "Continue after the response.",
                strategyRationale: "The current message needs a direct reply."
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        do {
            _ = try await coordinator.generate(chatID: chatID)
            XCTFail("Expected an incoming empty-reply result to be rejected")
        } catch let error as SuggestedRepliesError {
            XCTAssertEqual(error.code, "reply_schema_mismatch")
        }
        XCTAssertNil(try repository.suggestedReplyCache(chatID: chatID))
    }

    @MainActor
    func testUnknownLatestSenderSkipsProviderGeneration() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "synthetic-unknown-sender-chat"
        let message = ChatMessageRecord(
            chatID: chatID,
            senderKind: "unknown",
            senderName: nil,
            text: "Synthetic unresolved message",
            timeLabel: "",
            sortIndex: 0
        )
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(message)
        try container.mainContext.save()

        let service = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: service, repository: repository)

        do {
            _ = try await coordinator.generate(chatID: chatID)
            XCTFail("Expected sender review to be required")
        } catch let error as SuggestedRepliesError {
            XCTAssertEqual(error.code, "sender_review_required")
        }
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertNil(try coordinator.cachedReplies(chatID: chatID))
    }

    @MainActor
    func testAppLanguageReachesGenerationAndLegacyPromptCacheIsRegenerated()
        async throws
    {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "localized-prompt-version-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(
            aiService: client,
            repository: repository
        )
        let localization = LocalizationContext(languageIdentifier: "fr")

        _ = try await coordinator.generate(
            chatID: chatID,
            localization: localization
        )

        XCTAssertEqual(client.requests.map(\.appLanguage), ["fr"])
        let firstCache = try XCTUnwrap(
            repository.suggestedReplyCache(
                chatID: chatID,
                appLanguage: "fr"
            )
        )
        XCTAssertEqual(firstCache.promptVersion, SuggestedReplyPrompt.version)
        firstCache.promptVersion = SuggestedReplyPrompt.version - 1
        try container.mainContext.save()

        XCTAssertNil(
            try coordinator.cachedReplies(
                chatID: chatID,
                localization: localization
            )
        )
        _ = try await coordinator.generate(
            chatID: chatID,
            localization: localization
        )

        XCTAssertEqual(
            client.requests.map(\.appLanguage),
            ["fr", "fr"]
        )
        XCTAssertEqual(
            try repository.suggestedReplyCache(
                chatID: chatID,
                appLanguage: "fr"
            )?.promptVersion,
            SuggestedReplyPrompt.version
        )
        XCTAssertNil(
            try repository.suggestedReplyCache(
                chatID: chatID,
                appLanguage: "en"
            )
        )
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
        XCTAssertEqual(client.requests[0].existingHistorySummary, "")
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
        XCTAssertEqual(client.requests[1].olderMessagesToSummarize.map(\.text), ["Message 2"])
        XCTAssertEqual(client.requests[1].existingHistorySummary, "Summary through Message 1")
        XCTAssertNil(client.requests[1].previousConversationStrategy)

        let cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.summarizedMessageCount, 3)
        XCTAssertEqual(cache.historySummary, "Summary through Message 2")
        XCTAssertEqual(cache.replies.count, 2)
        XCTAssertEqual(cache.conversationStrategy, "Strategy 2")
        XCTAssertEqual(cache.strategyRationale, "Rationale 2")
    }

    @MainActor
    func testDeferredSummaryKeepsCheckpointAndResendsPendingPrefix() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "deferred-summary-chat"
        container.mainContext.insert(makeChat(id: chatID))
        for index in 0..<22 {
            container.mainContext.insert(makeMessage(chatID: chatID, index: index))
        }
        try container.mainContext.save()

        var callCount = 0
        let client = StubReplyService { request in
            callCount += 1
            return SuggestedReplyGenerationResult(
                historySummary: callCount == 1 ? nil : "Summary through Message 2",
                replies: ["First", "Second"],
                conversationStrategy: "Continue",
                strategyRationale: "Recent context is sufficient."
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)

        _ = try await coordinator.generate(chatID: chatID)
        var cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.summarizedMessageCount, 0)
        XCTAssertEqual(cache.historySummary, "")

        container.mainContext.insert(makeMessage(chatID: chatID, index: 22))
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[1].existingHistorySummary, "")
        XCTAssertEqual(
            client.requests[1].olderMessagesToSummarize.map(\.text),
            ["Message 0", "Message 1", "Message 2"])
        cache = try XCTUnwrap(repository.suggestedReplyCache(chatID: chatID))
        XCTAssertEqual(cache.summarizedMessageCount, 3)
        XCTAssertEqual(cache.historySummary, "Summary through Message 2")
    }

    @MainActor
    func testEditedSummarizedPrefixForcesFullRebuild() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "edited-prefix-chat"
        container.mainContext.insert(makeChat(id: chatID))
        var records: [ChatMessageRecord] = []
        for index in 0..<22 {
            let message = makeMessage(chatID: chatID, index: index)
            records.append(message)
            container.mainContext.insert(message)
        }
        try container.mainContext.save()

        let client = StubReplyService()
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)

        records[0].text = "Edited Message 0"
        try container.mainContext.save()
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[1].existingHistorySummary, "")
        XCTAssertEqual(
            client.requests[1].olderMessagesToSummarize.map(\.text),
            ["Edited Message 0", "Message 1"])
    }

    @MainActor
    func testUnavailablePersonaChangesDoNotConsumeLearningMessages() async throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let personaID = try PersonaRepository(container: container).defaultPersonaID()
        let chatID = "unavailable-persona-changes-chat"
        container.mainContext.insert(makeChat(id: chatID))
        container.mainContext.insert(makeMessage(chatID: chatID, index: 0))
        try container.mainContext.save()

        let client = StubReplyService { _ in
            SuggestedReplyGenerationResult(
                historySummary: nil,
                replies: ["First", "Second"],
                conversationStrategy: "",
                strategyRationale: "",
                personaObservationChangesAvailable: false
            )
        }
        let coordinator = SuggestedRepliesCoordinator(aiService: client, repository: repository)
        _ = try await coordinator.generate(chatID: chatID)

        XCTAssertFalse(
            try repository.personaLearningMessages(
                chatID: chatID,
                personaID: personaID,
                assignedAt: .distantPast
            ).isEmpty)
        XCTAssertEqual(try coordinator.cachedReplies(chatID: chatID)?.replies, ["First", "Second"])
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
        otherParticipantMessage.text = "Yes, dinner Tuesday at 7 works."
        let otherMessage = makeMessage(chatID: chatID, index: 2)
        otherMessage.senderKind = "group_participant"
        otherMessage.senderName = "Alex"
        otherMessage.sortIndex = 3
        let unknownMessage = makeMessage(chatID: chatID, index: 3)
        unknownMessage.senderKind = "unknown"
        unknownMessage.senderName = nil
        unknownMessage.sortIndex = 2

        container.mainContext.insert(makeChat(id: chatID))
        for message in [userMessage, otherParticipantMessage, otherMessage, unknownMessage] {
            container.mainContext.insert(message)
        }
        try container.mainContext.save()

        let client = StubReplyService { request in
            XCTAssertEqual(
                request.recentMessages.map(\.sender),
                ["user", "other_participant", "unknown", "group_participant"]
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
                        text: "Dinner together Tuesday at 7 PM",
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
        XCTAssertEqual(
            Set(activeMemories.map(\.text)),
            ["Asked about partner hotels in Beijing", "Dinner together Tuesday at 7 PM"]
        )
        XCTAssertTrue(activeMemories.allSatisfy { $0.origin == .ai })
    }

    @MainActor
    private func makeChat(id: String) -> ChatRecord {
        ChatRecord(
            id: id,
            title: "Sarah",
            previewText: "Preview"
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
