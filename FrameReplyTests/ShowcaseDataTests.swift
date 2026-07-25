#if DEBUG
    import SwiftData
    import XCTest

    @testable import FrameReply

    @MainActor
    final class ShowcaseDataTests: XCTestCase {
        func testShowcaseSeedsOnlyConfirmedFictionalChatsAndBuiltInPersonas() throws {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
            let personaRepository = PersonaRepository(container: container)
            try personaRepository.seedPersonasIfNeeded()
            try ShowcaseDataSeeder.seed(in: container)

            let chats = try container.mainContext.fetch(
                FetchDescriptor<ChatRecord>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
            )
            XCTAssertEqual(
                chats.map(\.id),
                ShowcaseScenario.chats.map(\.id)
            )
            XCTAssertTrue(chats.allSatisfy { !$0.isProvisional })
            XCTAssertTrue(chats.allSatisfy { $0.conversationKind == .direct })

            let messages = try container.mainContext.fetch(
                FetchDescriptor<ChatMessageRecord>()
            )
            XCTAssertEqual(
                messages.count,
                ShowcaseScenario.chats.flatMap(\.messages).count
            )
            XCTAssertFalse(messages.contains { $0.senderKind == "unknown" })

            let personas = try personaRepository.personas()
            XCTAssertEqual(
                personas.compactMap(\.builtInID),
                [.professional, .spark, .thoughtful]
            )
            XCTAssertEqual(try personaRepository.defaultPersona().builtInID, .professional)

            let contexts = try container.mainContext.fetch(
                FetchDescriptor<ChatContextRecord>()
            )
            let personaByID = Dictionary(
                uniqueKeysWithValues: personas.map { ($0.id, $0.builtInID) }
            )
            XCTAssertEqual(
                contexts.filter { personaByID[$0.personaID] == .thoughtful }.count,
                2
            )
            XCTAssertEqual(
                contexts.filter { personaByID[$0.personaID] == .professional }.count,
                1
            )
            XCTAssertEqual(
                contexts.filter { personaByID[$0.personaID] == .spark }.count,
                1
            )
        }

        func testMayaFixtureGroundsTheShowcaseRationaleAndMemory() throws {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
            try PersonaRepository(container: container).seedPersonasIfNeeded()
            try ShowcaseDataSeeder.seed(in: container)

            let repository = ChatRepository(container: container)
            let maya = try XCTUnwrap(
                ShowcaseScenario.chat(id: ShowcaseScenario.ChatID.maya)
            )
            XCTAssertEqual(
                try repository.messages(chatID: ShowcaseScenario.ChatID.maya).map(\.text),
                maya.messages.map(\.text)
            )
            XCTAssertEqual(
                try repository.chatMemories(chatID: ShowcaseScenario.ChatID.maya).map(\.text),
                [try XCTUnwrap(maya.memory).text]
            )
            let cache = try XCTUnwrap(
                repository.suggestedReplyCache(chatID: ShowcaseScenario.ChatID.maya)
            )
            XCTAssertEqual(cache.replies, maya.suggestedReplies)
            XCTAssertEqual(cache.conversationStrategy, maya.conversationStrategy)
            XCTAssertEqual(cache.strategyRationale, maya.strategyRationale)
        }

        func testSeededCachesAndStaticCoordinatorUseTheSameScenario() async throws {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
            try PersonaRepository(container: container).seedPersonasIfNeeded()
            try ShowcaseDataSeeder.seed(in: container)

            let repository = ChatRepository(container: container)
            let coordinator = ShowcaseSuggestedRepliesCoordinator()
            for scenario in ShowcaseScenario.chats {
                let outcome = try await coordinator.generate(
                    chatID: scenario.id,
                    draftingInput: nil,
                    force: true,
                    localization: LocalizationContext(locale: Locale(identifier: "en_US")),
                    traceID: ImportTraceID()
                )
                let cache = try XCTUnwrap(
                    repository.suggestedReplyCache(chatID: scenario.id)
                )

                XCTAssertEqual(outcome.replies, scenario.suggestedReplies)
                XCTAssertEqual(outcome.replies, cache.replies)
                XCTAssertEqual(outcome.conversationStrategy, cache.conversationStrategy)
                XCTAssertEqual(outcome.strategyRationale, cache.strategyRationale)
                XCTAssertEqual(outcome.source, .generated)
            }
        }
    }
#endif
