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

        let provider = ReplyProviderConfiguration()
        let client = StubReplyGenerator()
        let coordinator = SuggestedRepliesCoordinator(
            providerStore: provider,
            repository: repository,
            clientResolver: { _ in client }
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

        let client = StubReplyGenerator()
        let coordinator = SuggestedRepliesCoordinator(
            providerStore: ReplyProviderConfiguration(),
            repository: repository,
            clientResolver: { _ in client }
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

        let client = MutatingReplyGenerator {
            container.mainContext.insert(self.makeMessage(chatID: chatID, index: 1))
            try! container.mainContext.save()
        }
        let coordinator = SuggestedRepliesCoordinator(
            providerStore: ReplyProviderConfiguration(),
            repository: repository,
            clientResolver: { _ in client }
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

        let coordinator = SuggestedRepliesCoordinator(
            providerStore: ReplyProviderConfiguration(),
            repository: repository,
            clientResolver: { _ in StructuredFailureReplyGenerator() }
        )

        do {
            _ = try await coordinator.generate(chatID: chatID)
            XCTFail("Expected a reply-specific schema error")
        } catch let error as SuggestedRepliesError {
            XCTAssertEqual(error.code, "reply_schema_mismatch")
            XCTAssertTrue(error.localizedDescription.contains("generate replies"))
        }
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
private final class ReplyProviderConfiguration: ProviderConfigurationProviding {
    let activeProvider: ProviderConnection? = ProviderConnection(
        platform: .zaiInternational,
        model: .glm46VFlashX,
        lastValidatedAt: Date(),
        validationState: .connected
    )

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        "test-key"
    }
}

private final class StubReplyGenerator: SuggestedReplyGenerating, @unchecked Sendable {
    private(set) var requests: [SuggestedReplyGenerationRequest] = []
    private(set) var models: [ProviderModel] = []

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult {
        requests.append(request)
        models.append(model)
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

private final class MutatingReplyGenerator: SuggestedReplyGenerating {
    let mutate: () -> Void

    init(mutate: @escaping () -> Void) {
        self.mutate = mutate
    }

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult {
        mutate()
        return SuggestedReplyGenerationResult(
            historySummary: request.existingHistorySummary,
            replies: ["First", "Second"]
        )
    }
}

private final class StructuredFailureReplyGenerator: SuggestedReplyGenerating {
    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> SuggestedReplyGenerationResult {
        throw ProviderConnectionError.structuredOutput(
            ProviderStructuredOutputError(
                provider: "test",
                traceID: request.traceID,
                failure: StructuredOutputFailure(kind: .schemaMismatch, codingPath: "replies")
            )
        )
    }
}
