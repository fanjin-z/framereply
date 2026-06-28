import SwiftData
import XCTest
@testable import zeptly

final class ChatPersistenceTests: XCTestCase {
    @MainActor
    func testLegacyChatRowsDoNotRequireAvatarMetadata() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            insertChat(id: "legacy-chat", name: "Legacy Chat", into: container)
            try container.mainContext.save()
            let record = try XCTUnwrap(
                container.mainContext.fetch(FetchDescriptor<ChatRecord>()).first
            )
            record.avatarQuality = nil
            record.avatarAlgorithmRevision = nil
            try container.mainContext.save()
        }

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            let record = try XCTUnwrap(repository.chat(id: "legacy-chat"))
            XCTAssertNil(record.avatarQuality)
            XCTAssertNil(record.avatarAlgorithmRevision)
            XCTAssertTrue(try repository.storedAvatarFingerprints().isEmpty)
        }
    }

    @MainActor
    func testChatsPersistWhenTheContainerIsRecreated() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var importedChatID = ""

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            try repository.seedIfNeeded()
            let outcome = try repository.applyImport(
                analysis: provisionalAnalysis(),
                confirmedChatID: nil,
                provider: .deepSeek,
                model: .deepSeekV4Flash
            )
            importedChatID = outcome.chatID
        }

        do {
            let container = try ZeptlyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            XCTAssertEqual(try repository.chats().count, 1)
            XCTAssertEqual(try repository.messages(chatID: importedChatID).count, 1)
        }
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
        insertChat(
            id: "sarah-jenkins",
            name: "Sarah Jenkins",
            message: "Perfect. Please include a suggested time for the formal review too.",
            into: container
        )
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
        XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, 2)
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
        insertChat(id: "target-chat", name: "Target Chat", into: container)
        let originalCount = try repository.messages(chatID: "target-chat").count
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        try repository.mergeProvisionalChat(outcome.chatID, into: "target-chat")

        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertEqual(try repository.messages(chatID: "target-chat").count, originalCount + 1)
    }

    @MainActor
    func testDeleteChatRemovesRelatedDataAndLeavesOtherChatsUntouched() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        insertChat(id: "delete-me", name: "Delete Me", message: "Private", into: container)
        insertChat(id: "keep-me", name: "Keep Me", message: "Keep this", into: container)
        insertRelatedRecords(chatID: "delete-me", into: container)
        insertRelatedRecords(chatID: "keep-me", into: container)
        try container.mainContext.save()

        try repository.deleteChat(id: "delete-me")

        XCTAssertNil(try repository.chat(id: "delete-me"))
        XCTAssertTrue(try repository.messages(chatID: "delete-me").isEmpty)
        XCTAssertEqual(try relatedRecordCounts(chatID: "delete-me", in: container), [0, 0])

        XCTAssertNotNil(try repository.chat(id: "keep-me"))
        XCTAssertEqual(try repository.messages(chatID: "keep-me").count, 1)
        XCTAssertEqual(try relatedRecordCounts(chatID: "keep-me", in: container), [1, 1])
    }

    @MainActor
    func testDeleteProvisionalChatRemovesImportedData() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        try repository.deleteChat(id: outcome.chatID)

        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertTrue(try repository.messages(chatID: outcome.chatID).isEmpty)
        XCTAssertEqual(try relatedRecordCounts(chatID: outcome.chatID, in: container), [0, 0])
    }

    @MainActor
    func testDeleteMissingChatIsANoOp() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        insertChat(id: "keep-me", name: "Keep Me", into: container)
        try container.mainContext.save()

        try repository.deleteChat(id: "does-not-exist")

        XCTAssertNotNil(try repository.chat(id: "keep-me"))
    }

    @MainActor
    func testImportStoresAvatarAndMatchEvidenceWithoutScreenshotContent() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let analysis = ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            participants: ["Alex"],
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: "8:00 PM"
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0.4,
            sourceApp: "Telegram"
        )
        let artifact = avatarArtifact(quality: 0.72)
        let decision = ChatMatchDecision(
            disposition: .review,
            confirmedChatID: nil,
            suggestedChatID: "alex",
            aiConfidence: 0.4,
            avatarEvidence: .competing,
            transcriptEvidence: .weak,
            reason: .competingAvatar
        )

        let outcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: nil,
            matchDecision: decision,
            avatarArtifact: artifact,
            provider: .openAI,
            model: .gpt54Mini
        )

        let storedChat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertEqual(storedChat.avatarData, artifact.imageData)
        XCTAssertEqual(storedChat.avatarPerceptualHash, Int64(bitPattern: artifact.perceptualHash))
        XCTAssertEqual(storedChat.avatarQuality, artifact.quality)
        XCTAssertEqual(try repository.storedAvatarFingerprints().map(\.chatID), [outcome.chatID])

        let imports = try container.mainContext.fetch(FetchDescriptor<ChatImportRecord>())
        let importRecord = try XCTUnwrap(imports.first)
        XCTAssertEqual(importRecord.matchDisposition, ChatMatchDisposition.review.rawValue)
        XCTAssertEqual(importRecord.matchReason, ChatMatchReason.competingAvatar.rawValue)
        XCTAssertEqual(importRecord.avatarEvidence, AvatarEvidenceLevel.competing.rawValue)
        XCTAssertEqual(importRecord.transcriptEvidence, TranscriptEvidenceLevel.weak.rawValue)
        XCTAssertEqual(importRecord.sourceApp, "Telegram")

        try repository.deleteChat(id: outcome.chatID)
        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertTrue(try repository.storedAvatarFingerprints().isEmpty)
    }

    @MainActor
    func testManualMergeTransfersNewerValidProvisionalAvatar() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        insertChat(id: "target-chat", name: "Target Chat", into: container)
        try container.mainContext.save()
        let artifact = avatarArtifact(quality: 0.66)
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            avatarArtifact: artifact,
            provider: .deepSeek,
            model: .deepSeekV4Flash
        )

        try repository.mergeProvisionalChat(outcome.chatID, into: "target-chat")

        let target = try XCTUnwrap(repository.chat(id: "target-chat"))
        XCTAssertEqual(target.avatarData, artifact.imageData)
        XCTAssertEqual(target.avatarPerceptualHash, Int64(bitPattern: artifact.perceptualHash))
        XCTAssertEqual(target.avatarQuality, artifact.quality)
    }

    @MainActor
    private func insertChat(
        id: String,
        name: String,
        message: String? = nil,
        into container: ModelContainer
    ) {
        container.mainContext.insert(
            ChatRecord(
                id: id,
                name: name,
                lastActivityLabel: "Recent",
                preview: message ?? "Imported conversation",
                chipTitle: "General",
                chipSymbol: "number",
                avatarSymbol: nil,
                initials: "TC",
                appearanceStyle: 0,
                isUnread: false,
                isOnline: false
            )
        )
        if let message {
            container.mainContext.insert(
                ChatMessageRecord(
                    chatID: id,
                    senderKind: "contact",
                    text: message,
                    normalizedText: MessageTextNormalizer.normalize(message),
                    timeLabel: "10:50 AM",
                    sortIndex: 0
                )
            )
        }
    }

    @MainActor
    private func insertRelatedRecords(chatID: String, into container: ModelContainer) {
        container.mainContext.insert(
            ContactContextRecord(
                chatID: chatID,
                relationshipSubtitle: "Friend",
                relationshipNotes: "Notes",
                keyFactsJSON: "[]",
                currentInteractionGoal: "Reconnect",
                preferredPersona: "Friendly"
            )
        )
        container.mainContext.insert(
            ChatImportRecord(
                chatID: chatID,
                transcriptFingerprint: "fingerprint-\(chatID)",
                provider: "openAI",
                model: "gpt-5.4-mini",
                confidence: 0.9,
                insertedMessageCount: 1,
                isDuplicate: false,
                requiresReview: false
            )
        )
    }

    @MainActor
    private func relatedRecordCounts(chatID: String, in container: ModelContainer) throws -> [Int] {
        let contactRecords = try container.mainContext.fetch(
            FetchDescriptor<ContactContextRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let importRecords = try container.mainContext.fetch(
            FetchDescriptor<ChatImportRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        return [contactRecords.count, importRecords.count]
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

    private func avatarArtifact(quality: Double) -> AvatarArtifact {
        AvatarArtifact(
            imageData: Data(repeating: 0xA5, count: 512),
            perceptualHash: 0x1234_5678_9ABC_DEF0,
            featurePrintData: Data(repeating: 0x5A, count: 128),
            quality: quality,
            revision: AvatarArtifact.algorithmRevision
        )
    }
}
