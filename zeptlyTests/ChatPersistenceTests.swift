import SwiftData
import XCTest
@testable import zeptly

final class ChatPersistenceTests: XCTestCase {
    @MainActor
    func testChatsPersistWhenTheContainerIsRecreated() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            try ChatRepository(container: container).seedIfNeeded()
        }

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            XCTAssertEqual(try repository.chats().count, RezplySampleData.chats.count)
            XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, 5)
        }
    }

    @MainActor
    func testSeedingPersistsChatsMessagesAndContactContextOnce() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        try repository.seedIfNeeded()
        try repository.seedIfNeeded()

        let chats = try repository.chats()
        XCTAssertEqual(chats.count, RezplySampleData.chats.count)
        XCTAssertEqual(chats.first?.id, "sarah-jenkins")
        XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, 5)
        XCTAssertEqual(
            try repository.contactContext(chatID: "sarah-jenkins")?.preferredPersona,
            "Warm & Collaborative"
        )
    }

    @MainActor
    func testStoreSchemaContainsNoScreenshotPayload() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()

        let importRecord = ChatImportRecord(
            chatID: "sarah-jenkins",
            transcriptFingerprint: "fingerprint",
            provider: "openAI",
            model: "gpt-5.4-mini",
            confidence: 0.98,
            insertedMessageCount: 0,
            isDuplicate: true,
            requiresReview: false
        )
        container.mainContext.insert(importRecord)
        try container.mainContext.save()

        XCTAssertEqual(importRecord.transcriptFingerprint, "fingerprint")
        XCTAssertEqual(importRecord.insertedMessageCount, 0)
    }

    @MainActor
    func testImportMergesMessagesAndRepeatingTranscriptDoesNotDuplicateHistory() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Sarah Jenkins",
            participants: ["Sarah Jenkins"],
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: nil,
                    text: "Perfect. Please include a suggested time for the formal review too.",
                    timestampLabel: "10:50 AM"
                ),
                AnalyzedChatMessage(
                    sender: .user,
                    senderName: nil,
                    text: "I will send two options.",
                    timestampLabel: "10:52 AM"
                )
            ],
            matchedChatID: "sarah-jenkins",
            matchConfidence: 0.98
        )

        let first = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: "sarah-jenkins",
            provider: .openAI,
            model: .gpt54Mini
        )
        let second = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: "sarah-jenkins",
            provider: .openAI,
            model: .gpt54Mini
        )

        XCTAssertEqual(first.insertedMessageCount, 1)
        XCTAssertFalse(first.duplicate)
        XCTAssertEqual(second.insertedMessageCount, 0)
        XCTAssertTrue(second.duplicate)
        XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, 6)
    }

    @MainActor
    func testUnconfirmedImportCreatesProvisionalChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            participants: ["Alex"],
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0.3
        )

        let outcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: nil,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        XCTAssertTrue(outcome.reviewRequired)
        XCTAssertFalse(outcome.matchedExisting)
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.name, "Weekend Hike")
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.isProvisional, true)
    }

    @MainActor
    func testProvisionalChatCanBeRenamedAndConfirmed() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        try repository.confirmProvisionalChat(chatID: outcome.chatID, name: "Alex Hiking")

        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.name, "Alex Hiking")
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.isProvisional, false)
    }

    @MainActor
    func testProvisionalChatCanMergeIntoExistingChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let originalCount = try repository.messages(chatID: "sarah-jenkins").count
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        try repository.mergeProvisionalChat(outcome.chatID, into: "sarah-jenkins")

        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, originalCount + 1)
    }

    private func provisionalAnalysis() -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            participants: ["Alex"],
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0.3
        )
    }
}
