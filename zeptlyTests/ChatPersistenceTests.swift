import SwiftData
import XCTest

@testable import zeptly

@MainActor
final class ChatPersistenceTests: XCTestCase {
    func testDraftingInputTransitionsFromPendingToSubmittedAndIsOneUse() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let operationID = UUID()
        let current = ChatImportRecord(
            chatID: "chat", transcriptFingerprint: nil, provider: "test", model: "test",
            confidence: 1, insertedMessageCount: 1, isDuplicate: false, requiresReview: false,
            operationID: operationID, draftingInputStateRaw: DraftingInputState.pending.rawValue
        )
        container.mainContext.insert(current)
        try container.mainContext.save()
        let now = Date()

        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: current.id, operationID: operationID, now: now),
            .pending
        )
        XCTAssertEqual(
            try repository.resolveDraftingInput(
                "  Make this warmer  ", importID: current.id, operationID: operationID, now: now
            ),
            .submitted
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: current.id, operationID: operationID, now: now),
            .submitted("Make this warmer")
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: current.id, operationID: operationID, now: now),
            .alreadyConsumed
        )
    }

    func testBlankDraftingInputBecomesSkipped() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let operationID = UUID()
        let record = makePendingImport(operationID: operationID)
        container.mainContext.insert(record)
        try container.mainContext.save()

        XCTAssertEqual(
            try repository.resolveDraftingInput(" \n ", importID: record.id, operationID: operationID),
            .skipped
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: record.id, operationID: operationID),
            .skipped
        )
    }

    func testDraftingInputExpiryAndOperationMismatch() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let operationID = UUID()
        let expired = makePendingImport(operationID: operationID)
        container.mainContext.insert(expired)
        try container.mainContext.save()
        let now = Date()

        try repository.resolveDraftingInput(
            "Old draft", importID: expired.id, operationID: operationID, now: now.addingTimeInterval(-901)
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: expired.id, operationID: operationID, now: now),
            .expired
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(importID: expired.id, operationID: UUID(), now: now),
            .operationMismatch
        )

        try repository.resolveDraftingInput(
            "Another old draft", importID: expired.id, operationID: operationID, now: now.addingTimeInterval(-901)
        )
        try repository.purgeExpiredDraftingInputs(now: now)
        XCTAssertNil(expired.draftingInput)
    }

    func testFreshContextObservesInputCommittedByAnotherContext() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let operationID = UUID()
        let record = makePendingImport(operationID: operationID)
        container.mainContext.insert(record)
        try container.mainContext.save()

        let staleRepository = ChatRepository(context: ModelContext(container))
        XCTAssertEqual(try staleRepository.importRecord(id: record.id)?.draftingInputStateRaw, "pending")

        let writer = ChatRepository(context: ModelContext(container))
        try writer.resolveDraftingInput("Use Friday", importID: record.id, operationID: operationID)

        let freshReader = ChatRepository(context: ModelContext(container))
        XCTAssertEqual(
            try freshReader.consumeDraftingInputIfReady(importID: record.id, operationID: operationID),
            .submitted("Use Friday")
        )
    }

    func testDraftingInputBarrierWaitsForReadyState() async throws {
        let sequence = DraftingInputTestSequence([.pending, .pending, .submitted("Ready")])
        let result = try await DraftingInputBarrier.waitUntilReady(pollInterval: .milliseconds(1)) {
            await sequence.next()
        }
        XCTAssertEqual(result, .submitted("Ready"))
        let readCount = await sequence.readCount
        XCTAssertEqual(readCount, 3)
    }

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
                provider: .openAI,
                model: .gpt54Mini
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

    func testUnconfirmedImportUsesReliableSenderNameForProvisionalChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let analysis = ChatImportAnalysis(
            conversationTitle: nil,
            messages: [
                AnalyzedChatMessage(
                    sender: .user,
                    senderName: "Device Owner",
                    text: "Want to meet?",
                    timestampLabel: nil
                ),
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Uncertain Name",
                    text: "Maybe",
                    timestampLabel: nil
                ),
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0
        )

        let outcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: nil,
            provider: .openAI,
            model: .gpt54Mini
        )

        XCTAssertTrue(outcome.reviewRequired)
        XCTAssertFalse(outcome.matchedExisting)
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.name, "Alex")
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.isProvisional, true)
    }

    func testProvisionalChatCanBeRenamedAndConfirmed() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .openAI,
            model: .gpt54Mini
        )

        try repository.confirmProvisionalChat(chatID: outcome.chatID, name: "Alex Hiking")

        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.name, "Alex Hiking")
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.isProvisional, false)
    }

    func testProvisionalChatCanMergeIntoExistingChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        insertChat(id: "target-chat", name: "Target Chat", into: container)
        let originalCount = try repository.messages(chatID: "target-chat").count
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil,
            provider: .openAI,
            model: .gpt54Mini
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: outcome.chatID,
                value: ContactMemory(text: "Met on the trail")
            )
        )
        insertReplyCache(chatID: outcome.chatID, into: container)
        try container.mainContext.save()

        try repository.mergeProvisionalChat(outcome.chatID, into: "target-chat")

        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertNil(try repository.suggestedReplyCache(chatID: outcome.chatID))
        XCTAssertEqual(try repository.messages(chatID: "target-chat").count, originalCount + 1)
        XCTAssertTrue(try repository.contactMemories(chatID: outcome.chatID).isEmpty)
        XCTAssertEqual(try repository.contactMemories(chatID: "target-chat").map(\.text), ["Met on the trail"])
    }

    func testAtomicContactMemoriesPreserveMultilineTextAndMetadata() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chatID = "memory-chat"
        insertChat(id: chatID, name: "Memory", into: container)
        let sourceID = UUID()
        let memory = ContactMemory(
            text: "Met at university.\nPlanning a reunion next spring.",
            kind: .relationship,
            origin: .ai,
            certainty: .aiInferred,
            sourceMessageIDs: [sourceID]
        )
        container.mainContext.insert(ContactMemoryRecord(chatID: chatID, value: memory))
        try container.mainContext.save()

        let stored = try XCTUnwrap(repository.contactMemories(chatID: chatID).first?.value)
        XCTAssertEqual(stored.id, memory.id)
        XCTAssertEqual(stored.text, memory.text)
        XCTAssertEqual(stored.kind, .relationship)
        XCTAssertEqual(stored.origin, .ai)
        XCTAssertEqual(stored.certainty, .aiInferred)
        XCTAssertEqual(stored.status, .active)
        XCTAssertEqual(stored.sourceMessageIDs, [sourceID])
    }

    func testDeleteChatRemovesRelatedDataAndLeavesOtherChatsUntouched() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        insertChat(id: "delete-me", name: "Delete Me", message: "Private", into: container)
        insertChat(id: "keep-me", name: "Keep Me", message: "Keep this", into: container)
        insertRelatedRecords(chatID: "delete-me", into: container)
        insertRelatedRecords(chatID: "keep-me", into: container)
        insertReplyCache(chatID: "delete-me", into: container)
        insertReplyCache(chatID: "keep-me", into: container)
        try container.mainContext.save()

        try repository.deleteChat(id: "delete-me")
        try repository.deleteChat(id: "does-not-exist")

        XCTAssertNil(try repository.chat(id: "delete-me"))
        XCTAssertTrue(try repository.messages(chatID: "delete-me").isEmpty)
        XCTAssertEqual(try relatedRecordCounts(chatID: "delete-me", in: container), [0, 0, 0])
        XCTAssertNil(try repository.suggestedReplyCache(chatID: "delete-me"))

        XCTAssertNotNil(try repository.chat(id: "keep-me"))
        XCTAssertEqual(try repository.messages(chatID: "keep-me").count, 1)
        XCTAssertEqual(try relatedRecordCounts(chatID: "keep-me", in: container), [1, 1, 1])
        XCTAssertNotNil(try repository.suggestedReplyCache(chatID: "keep-me"))
    }

    func testImportStoresAvatarAndMatchEvidenceWithoutRemovedAIAppMetadata() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let analysis = ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: "8:00 PM"
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0
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
        XCTAssertNil(importRecord.sourceApp)

        try repository.deleteChat(id: outcome.chatID)
        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertTrue(try repository.storedAvatarFingerprints().isEmpty)
    }

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
            provider: .openAI,
            model: .gpt54Mini
        )

        try repository.mergeProvisionalChat(outcome.chatID, into: "target-chat")

        let target = try XCTUnwrap(repository.chat(id: "target-chat"))
        XCTAssertEqual(target.avatarData, artifact.imageData)
        XCTAssertEqual(target.avatarPerceptualHash, Int64(bitPattern: artifact.perceptualHash))
        XCTAssertEqual(target.avatarQuality, artifact.quality)
    }

    func testUnknownSenderRequiresReviewAndCanBeResolvedWithoutPersistingQuote() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        insertChat(id: "known-chat", name: "Known Chat", into: container)
        try container.mainContext.save()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Known Chat",
            messages: [
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Alex",
                    text: "I remember",
                    timestampLabel: "12:19 AM",
                    outerAlignment: .fullWidth,
                    outerAuthorLabel: "Alex",
                    senderConfidence: 0.2,
                    senderEvidence: .insufficient,
                    quotedReply: AnalyzedQuotedReply(
                        sender: .user,
                        senderName: nil,
                        text: "I live in Guangzhou"
                    )
                )
            ],
            matchedChatID: "known-chat",
            matchConfidence: 0.95,
            ownershipConvention: .unobservable
        )

        let outcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: "known-chat",
            provider: .openAI,
            model: .gpt54Mini
        )
        let stored = try XCTUnwrap(repository.messages(chatID: "known-chat").first)
        let importBefore = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ChatImportRecord>()).first
        )
        let fingerprintBefore = importBefore.transcriptFingerprint

        XCTAssertTrue(outcome.reviewRequired)
        XCTAssertEqual(stored.senderKind, "unknown")
        XCTAssertEqual(stored.text, "I remember")
        XCTAssertFalse(try repository.messages(chatID: "known-chat").contains { $0.text == "I live in Guangzhou" })
        XCTAssertTrue(importBefore.requiresReview)

        try repository.resolveUnknownSender(messageID: stored.id, as: .contact)

        XCTAssertEqual(try repository.messages(chatID: "known-chat").first?.senderKind, "contact")
        XCTAssertFalse(importBefore.requiresReview)
        XCTAssertNotEqual(importBefore.transcriptFingerprint, fingerprintBefore)
    }

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

    private func insertRelatedRecords(chatID: String, into container: ModelContainer) {
        container.mainContext.insert(
            ContactContextRecord(
                chatID: chatID,
                relationshipSubtitle: "Friend",
                currentInteractionGoal: "Reconnect",
                preferredPersona: "Friendly"
            )
        )
        container.mainContext.insert(
            ContactMemoryRecord(
                chatID: chatID,
                value: ContactMemory(text: "Notes")
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

    private func makePendingImport(operationID: UUID) -> ChatImportRecord {
        ChatImportRecord(
            chatID: "chat", transcriptFingerprint: nil, provider: "test", model: "test",
            confidence: 1, insertedMessageCount: 1, isDuplicate: false, requiresReview: false,
            operationID: operationID, draftingInputStateRaw: DraftingInputState.pending.rawValue
        )
    }

    private func insertReplyCache(chatID: String, into container: ModelContainer) {
        container.mainContext.insert(
            SuggestedReplyCacheRecord(
                chatID: chatID,
                historySummary: "Summary",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: "fingerprint",
                repliesJSON: "[\"One\",\"Two\"]",
                inputFingerprint: "input",
                provider: "openAI",
                model: "gpt-5.4-mini",
                promptVersion: SuggestedReplyPrompt.version
            )
        )
    }

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
        let memoryRecords = try container.mainContext.fetch(
            FetchDescriptor<ContactMemoryRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        return [contactRecords.count, memoryRecords.count, importRecords.count]
    }

    private func provisionalAnalysis() -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0
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

private actor DraftingInputTestSequence {
    private var values: [DraftingInputConsumption]
    private(set) var readCount = 0

    init(_ values: [DraftingInputConsumption]) {
        self.values = values
    }

    func next() -> DraftingInputConsumption {
        readCount += 1
        return values.removeFirst()
    }
}
