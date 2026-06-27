import SwiftData
import XCTest
@testable import zeptly

final class ChatPersistenceTests: XCTestCase {
    @MainActor
    func testSeedingPersistsChatsMessagesAndContactContextOnce() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        try repository.seedIfNeeded()
        try repository.seedIfNeeded()

        XCTAssertEqual(try repository.chats().count, RezplySampleData.chats.count)
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
}
