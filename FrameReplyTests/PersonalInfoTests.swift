import SwiftData
import XCTest

@testable import FrameReply

final class PersonalInfoReconcilerTests: XCTestCase {
    func testReconcilesOnlySupportedChangesAndProtectsUserItems() throws {
        let evidenceID = UUID()
        let disallowedID = UUID()
        let aiFact = PersonalInfoFact(
            text: "Prefers tea", origin: .ai
        )
        let protectedFact = PersonalInfoFact(text: "Lives in Toronto")
        let staleAIFact = PersonalInfoFact(
            text: "Runs marathons", origin: .ai
        )

        let result = PersonalInfoReconciler.reconcile(
            facts: [aiFact, protectedFact, staleAIFact],
            changes: [
                PersonalInfoChange(
                    action: .update, targetFactID: aiFact.id, text: "Prefers coffee",
                    sourceMessageIDs: [evidenceID]
                ),
                PersonalInfoChange(
                    action: .archive, targetFactID: protectedFact.id, text: nil,
                    sourceMessageIDs: [evidenceID]
                ),
                PersonalInfoChange(
                    action: .archive, targetFactID: staleAIFact.id, text: nil,
                    sourceMessageIDs: [evidenceID]
                ),
                PersonalInfoChange(
                    action: .add, targetFactID: nil, text: "Runs marathons",
                    sourceMessageIDs: [evidenceID]
                ),
                PersonalInfoChange(
                    action: .add, targetFactID: nil, text: "Vegetarian",
                    sourceMessageIDs: [disallowedID]
                ),
                PersonalInfoChange(
                    action: .add, targetFactID: nil, text: "Speaks French",
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedUserSourceMessageIDs: [evidenceID]
        )

        XCTAssertEqual(result.first { $0.id == aiFact.id }?.text, "Prefers coffee")
        XCTAssertNotNil(result.first { $0.id == protectedFact.id })
        XCTAssertNil(result.first { $0.id == staleAIFact.id })
        XCTAssertNil(result.first { $0.text == "Vegetarian" })
        XCTAssertNotNil(result.first { $0.text == "Runs marathons" })
        XCTAssertNotNil(result.first { $0.text == "Speaks French" && $0.origin == .ai })
    }

    func testEnforcesUnicodeLengthCapacityAndEightChangeLimit() {
        let evidenceID = UUID()
        let accepted = String(repeating: "a", count: 118) + "e\u{301}"
        let rejected = String(repeating: "b", count: 119) + "e\u{301}"
        XCTAssertEqual(accepted.unicodeScalars.count, 120)
        XCTAssertEqual(rejected.unicodeScalars.count, 121)

        var changes = [
            PersonalInfoChange(
                action: .add, targetFactID: nil, text: accepted,
                sourceMessageIDs: [evidenceID]
            ),
            PersonalInfoChange(
                action: .add, targetFactID: nil, text: rejected,
                sourceMessageIDs: [evidenceID]
            )
        ]
        changes += (0..<8).map {
            PersonalInfoChange(
                action: .add, targetFactID: nil, text: "Fact \($0)",
                sourceMessageIDs: [evidenceID]
            )
        }
        let result = PersonalInfoReconciler.reconcile(
            facts: [], changes: changes, allowedUserSourceMessageIDs: [evidenceID]
        )
        XCTAssertEqual(result.count, 7)
        XCTAssertNotNil(result.first { $0.text == accepted })
        XCTAssertNil(result.first { $0.text == rejected })

        let atCapacity = (0..<PersonalInfoLimits.maximumActiveFacts).map {
            PersonalInfoFact(text: "Existing \($0)")
        }
        let capacityResult = PersonalInfoReconciler.reconcile(
            facts: atCapacity,
            changes: [
                PersonalInfoChange(
                    action: .add, targetFactID: nil, text: "One too many",
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedUserSourceMessageIDs: [evidenceID]
        )
        XCTAssertEqual(capacityResult, atCapacity)
    }
}

@MainActor
final class PersonalInfoPersistenceTests: XCTestCase {
    func testSchemaMigrationPreservesExistingChatsAndMessages() throws {
        let storeURL = FileManager.default.temporaryDirectory.appending(
            path: "PersonalInfoMigration-\(UUID().uuidString).store"
        )
        defer {
            for url in [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm")
            ] where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let legacySchema = Schema([
            ChatRecord.self,
            SelfAliasRecord.self,
            SelfAliasAssociationRecord.self,
            ChatMessageRecord.self,
            ChatContextRecord.self,
            ChatMemoryRecord.self,
            PersonaRecord.self,
            PersonaObservationRecord.self,
            SuggestedReplyCacheRecord.self,
            ChatImportRecord.self,
            StoreMetadataRecord.self
        ])
        do {
            let configuration = ModelConfiguration(
                FrameReplyDataStore.configurationName,
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema, configurations: [configuration]
            )
            legacyContainer.mainContext.insert(
                ChatRecord(id: "legacy-chat", title: "Legacy", previewText: "Still here")
            )
            legacyContainer.mainContext.insert(
                ChatMessageRecord(
                    chatID: "legacy-chat",
                    senderKind: "user",
                    text: "Existing message",
                    timeLabel: "",
                    sortIndex: 0
                )
            )
            try legacyContainer.mainContext.save()
        }

        let migratedContainer = try FrameReplyDataStore.makeContainer(url: storeURL)
        let repository = ChatRepository(container: migratedContainer)
        XCTAssertEqual(try repository.chat(id: "legacy-chat")?.title, "Legacy")
        XCTAssertEqual(
            try repository.messages(chatID: "legacy-chat").map(\.text),
            ["Existing message"]
        )
        XCTAssertTrue(try repository.personalInfoFacts().isEmpty)
        XCTAssertTrue(try repository.personalInfoLearningEnabled())
    }

    func testManualFactsEnforceCapacityAndDeletionAllowsFutureRelearning() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        for index in 0..<PersonalInfoLimits.maximumActiveFacts {
            try repository.addPersonalInfoFact(text: "Personal item \(index)")
        }
        XCTAssertThrowsError(try repository.addPersonalInfoFact(text: "Overflow")) {
            XCTAssertEqual($0 as? PersonalInfoError, .activeFactLimitReached)
        }

        let first = try XCTUnwrap(try repository.personalInfoFacts().first)
        try repository.updatePersonalInfoFact(first, text: "Corrected personal item")
        XCTAssertEqual(first.origin, PersonalInfoFactOrigin.user.rawValue)

        let deletedID = first.id
        let deletedText = first.text
        try repository.deletePersonalInfoFact(first)
        XCTAssertFalse(try repository.personalInfoFacts().contains { $0.id == deletedID })

        XCTAssertNoThrow(try repository.addPersonalInfoFact(text: deletedText))
        XCTAssertEqual(
            try repository.personalInfoFacts().filter { $0.text == deletedText }.count,
            1
        )
    }

    func testLearningToggleDefaultsOnAndPersists() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        XCTAssertTrue(try repository.personalInfoLearningEnabled())
        try repository.setPersonalInfoLearningEnabled(false)
        XCTAssertFalse(try ChatRepository(container: container).personalInfoLearningEnabled())
        try repository.setPersonalInfoLearningEnabled(true)
        XCTAssertTrue(try ChatRepository(container: container).personalInfoLearningEnabled())
    }

    func testChatDeletionKeepsAccountFacts() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "personal-info-delete-chat"
        container.mainContext.insert(
            ChatRecord(id: chatID, title: "Contact", previewText: "Preview")
        )
        container.mainContext.insert(
            message(chatID: chatID, index: 0, sender: "user", createdAt: 1)
        )
        try repository.addPersonalInfoFact(text: "Global fact")
        try container.mainContext.save()

        try repository.deleteChat(id: chatID)
        XCTAssertEqual(try repository.personalInfoFacts().count, 1)
        XCTAssertTrue(try repository.messages(chatID: chatID).isEmpty)
    }

    private func message(
        chatID: String, index: Int, sender: String, createdAt: TimeInterval
    ) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID,
            senderKind: sender,
            text: "Message \(index)",
            timeLabel: "",
            sortIndex: index,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}
