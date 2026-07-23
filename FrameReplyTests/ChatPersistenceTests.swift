import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class ChatPersistenceTests: XCTestCase {
    func testDraftingInputLifecycleAcrossContexts() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let operationID = UUID()
        let current = ChatImportRecord(
            chatID: "chat", transcriptFingerprint: nil,
            insertedMessageCount: 1, isDuplicate: false, requiresReview: false,
            operationID: operationID, draftingInputStateRaw: DraftingInputState.pending.rawValue
        )
        container.mainContext.insert(current)
        try container.mainContext.save()
        let now = Date()

        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: current.id, operationID: operationID, now: now),
            .pending
        )
        XCTAssertEqual(
            try repository.resolveDraftingInput(
                "  Make this warmer  ", importID: current.id, operationID: operationID, now: now
            ),
            .submitted
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: current.id, operationID: operationID, now: now),
            .submitted("Make this warmer")
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: current.id, operationID: operationID, now: now),
            .alreadyConsumed
        )

        let skipped = makePendingImport(operationID: operationID)
        container.mainContext.insert(skipped)
        try container.mainContext.save()
        XCTAssertEqual(
            try repository.resolveDraftingInput(
                " \n ", importID: skipped.id, operationID: operationID),
            .skipped
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: skipped.id, operationID: operationID),
            .skipped
        )

        let overlong = makePendingImport(operationID: operationID)
        container.mainContext.insert(overlong)
        try container.mainContext.save()
        XCTAssertThrowsError(
            try repository.resolveDraftingInput(
                String(repeating: "a", count: 501),
                importID: overlong.id,
                operationID: operationID
            )
        ) { error in
            XCTAssertEqual(
                error as? DraftingInputError,
                .tooLong(maximum: DraftingInputLimits.maximumCharacterCount)
            )
        }
        XCTAssertEqual(overlong.draftingInputStateRaw, DraftingInputState.pending.rawValue)
        XCTAssertNil(overlong.draftingInput)

        let expired = makePendingImport(operationID: operationID)
        container.mainContext.insert(expired)
        try container.mainContext.save()
        try repository.resolveDraftingInput(
            "Old draft", importID: expired.id, operationID: operationID,
            now: now.addingTimeInterval(-901)
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: expired.id, operationID: operationID, now: now),
            .expired
        )
        XCTAssertEqual(
            try repository.consumeDraftingInputIfReady(
                importID: expired.id, operationID: UUID(), now: now),
            .operationMismatch
        )

        try repository.resolveDraftingInput(
            "Another old draft", importID: expired.id, operationID: operationID,
            now: now.addingTimeInterval(-901)
        )
        try repository.purgeExpiredDraftingInputs(now: now)
        XCTAssertNil(expired.draftingInput)

        let crossContextContainer = try FrameReplyDataStore.makeContainer(inMemory: true)
        let crossContextOperationID = UUID()
        let record = makePendingImport(operationID: crossContextOperationID)
        crossContextContainer.mainContext.insert(record)
        try crossContextContainer.mainContext.save()

        let staleRepository = ChatRepository(context: ModelContext(crossContextContainer))
        XCTAssertEqual(
            try staleRepository.importRecord(id: record.id)?.draftingInputStateRaw, "pending")

        let writer = ChatRepository(context: ModelContext(crossContextContainer))
        try writer.resolveDraftingInput(
            "Use Friday",
            importID: record.id,
            operationID: crossContextOperationID
        )

        let freshReader = ChatRepository(context: ModelContext(crossContextContainer))
        XCTAssertEqual(
            try freshReader.consumeDraftingInputIfReady(
                importID: record.id,
                operationID: crossContextOperationID
            ),
            .submitted("Use Friday")
        )
    }

    func testChatsPersistWhenTheContainerIsRecreated() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var importedChatID = ""

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            try repository.seedIfNeeded()
            let outcome = try repository.applyImport(
                analysis: provisionalAnalysis(),
                confirmedChatID: nil
            )
            importedChatID = outcome.chatID
        }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            XCTAssertEqual(try repository.chats().count, 1)
            XCTAssertEqual(try repository.messages(chatID: importedChatID).count, 1)
        }
    }

    func testImportMergesMessagesAndRepeatingTranscriptDoesNotDuplicateHistory() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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
                    sender: .otherParticipant,
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
            confirmedChatID: "sarah-jenkins"
        )
        let second = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: "sarah-jenkins"
        )

        XCTAssertEqual(first.insertedMessageCount, 1)
        XCTAssertFalse(first.duplicate)
        XCTAssertEqual(second.insertedMessageCount, 0)
        XCTAssertTrue(second.duplicate)
        XCTAssertEqual(try repository.messages(chatID: "sarah-jenkins").count, 2)
    }

    func testProvisionalAndUnknownSenderIdentityLifecycle() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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
                    sender: .otherParticipant,
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
            confirmedChatID: nil
        )

        XCTAssertTrue(outcome.reviewRequired)
        XCTAssertFalse(outcome.matchedExisting)
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.title, "Alex")
        XCTAssertEqual(try repository.chat(id: outcome.chatID)?.isProvisional, true)
        XCTAssertEqual(
            try repository.chat(id: outcome.chatID)?.importReviewState?.identityStatus,
            .needsReview
        )

        let unresolvedMessage = try XCTUnwrap(
            repository.messages(chatID: outcome.chatID).first {
                $0.senderKind == "unknown"
            }
        )
        try repository.resolveUnknownSender(
            messageID: unresolvedMessage.id,
            as: .otherParticipant
        )
        try repository.confirmProvisionalChat(chatID: outcome.chatID, name: "Alex Hiking")

        let chat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertEqual(chat.title, "Alex Hiking")
        XCTAssertFalse(chat.isProvisional)
        XCTAssertEqual(chat.importReviewState?.identityStatus, .confirmed)

        let reviewContainer = try FrameReplyDataStore.makeContainer(inMemory: true)
        let reviewRepository = ChatRepository(container: reviewContainer)
        insertChat(id: "known-chat", name: "Known Chat", into: reviewContainer)
        try reviewContainer.mainContext.save()
        let unknownAnalysis = ChatImportAnalysis(
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
                    senderEvidence: .insufficient
                )
            ],
            matchedChatID: "known-chat",
            matchConfidence: 0.95,
            ownershipConvention: .unobservable
        )
        let unknownOutcome = try reviewRepository.applyImport(
            analysis: unknownAnalysis,
            confirmedChatID: "known-chat"
        )
        let stored = try XCTUnwrap(reviewRepository.messages(chatID: "known-chat").first)
        let importBefore = try XCTUnwrap(
            reviewContainer.mainContext.fetch(FetchDescriptor<ChatImportRecord>()).first
        )
        let fingerprintBefore = importBefore.transcriptFingerprint

        XCTAssertTrue(unknownOutcome.reviewRequired)
        XCTAssertEqual(stored.senderKind, "unknown")
        XCTAssertTrue(importBefore.requiresReview)

        try reviewRepository.resolveUnknownSender(messageID: stored.id, as: .otherParticipant)

        XCTAssertEqual(
            try reviewRepository.messages(chatID: "known-chat").first?.senderKind,
            "other_participant"
        )
        XCTAssertEqual(
            try reviewRepository.participantAliases(chatID: "known-chat").map(\.normalizedLabel),
            ["alex"]
        )
        XCTAssertFalse(importBefore.requiresReview)
        XCTAssertNotEqual(importBefore.transcriptFingerprint, fingerprintBefore)
    }

    func testProvisionalReviewRetiresOnlyAfterEnoughResolvedActivity() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil
        )
        let importRecord = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ChatImportRecord>()).first
        )

        XCTAssertTrue(try XCTUnwrap(repository.chat(id: outcome.chatID)).isProvisional)
        XCTAssertTrue(importRecord.requiresReview)

        try repository.recordImportReviewExposure(chatID: outcome.chatID)
        try repository.recordImportReviewMeaningfulAction(chatID: outcome.chatID)

        var chat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertEqual(chat.importReviewState?.viewCount, 1)
        XCTAssertEqual(chat.importReviewState?.meaningfulActionCount, 1)
        XCTAssertTrue(chat.isProvisional)
        XCTAssertEqual(chat.importReviewState?.identityStatus, .needsReview)

        try repository.recordImportReviewMeaningfulAction(chatID: outcome.chatID)

        chat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertFalse(chat.isProvisional)
        XCTAssertEqual(chat.importReviewState?.meaningfulActionCount, 2)
        XCTAssertEqual(chat.importReviewState?.identityStatus, .dismissed)
        XCTAssertFalse(importRecord.requiresReview)

        let unknownContainer = try FrameReplyDataStore.makeContainer(inMemory: true)
        let unknownRepository = ChatRepository(container: unknownContainer)
        let unknownAnalysis = ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            messages: [
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0
        )
        let unknownOutcome = try unknownRepository.applyImport(
            analysis: unknownAnalysis,
            confirmedChatID: nil
        )

        try unknownRepository.recordImportReviewExposure(chatID: unknownOutcome.chatID)
        try unknownRepository.recordImportReviewMeaningfulAction(chatID: unknownOutcome.chatID)
        try unknownRepository.recordImportReviewMeaningfulAction(chatID: unknownOutcome.chatID)

        let unresolvedChat = try XCTUnwrap(
            unknownRepository.chat(id: unknownOutcome.chatID)
        )
        XCTAssertTrue(unresolvedChat.isProvisional)
        XCTAssertEqual(unresolvedChat.importReviewState?.identityStatus, .needsReview)
    }

    func testChatContextIsCreatedAndGoalAndPersonaUpdatesAreExplicit() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let personas = PersonaRepository(container: container)
        try personas.seedPersonasIfNeeded()
        insertChat(id: "brief-chat", name: "Brief", into: container)

        let initial = try repository.ensureChatContext(chatID: "brief-chat")
        XCTAssertEqual(initial.currentInteractionGoal, "")
        XCTAssertFalse(try repository.updateInteractionGoal(chatID: "brief-chat", goal: ""))
        XCTAssertTrue(
            try repository.updateInteractionGoal(
                chatID: "brief-chat", goal: "  Agree on dinner plans  "))
        XCTAssertEqual(initial.currentInteractionGoal, "Agree on dinner plans")

        let replacement = try XCTUnwrap(
            try personas.personas().first { $0.id != initial.personaID })
        let assignedAt = Date(timeIntervalSince1970: 1234)
        XCTAssertTrue(
            try repository.assignPersona(
                personaID: replacement.id,
                toChatID: "brief-chat",
                at: assignedAt
            ))
        XCTAssertEqual(initial.personaID, replacement.id)
        XCTAssertEqual(initial.personaAssignedAt, assignedAt)
        XCTAssertFalse(
            try repository.assignPersona(personaID: replacement.id, toChatID: "brief-chat"))
    }

    func testProvisionalChatCanMergeIntoExistingChat() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        insertChat(id: "target-chat", name: "Target Chat", into: container)
        let originalCount = try repository.messages(chatID: "target-chat").count
        let outcome = try repository.applyImport(
            analysis: provisionalAnalysis(),
            confirmedChatID: nil
        )
        container.mainContext.insert(
            ChatMemoryRecord(
                chatID: outcome.chatID,
                value: ChatMemory(text: "Met on the trail")
            )
        )
        insertReplyCache(chatID: outcome.chatID, into: container)
        try container.mainContext.save()

        try repository.mergeProvisionalChat(outcome.chatID, into: "target-chat")

        XCTAssertNil(try repository.chat(id: outcome.chatID))
        XCTAssertNil(try repository.suggestedReplyCache(chatID: outcome.chatID))
        XCTAssertEqual(try repository.messages(chatID: "target-chat").count, originalCount + 1)
        XCTAssertTrue(try repository.chatMemories(chatID: outcome.chatID).isEmpty)
        XCTAssertEqual(
            try repository.chatMemories(chatID: "target-chat").map(\.text), ["Met on the trail"])
    }

    func testDeleteChatRemovesRelatedDataAndLeavesOtherChatsUntouched() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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
        XCTAssertEqual(
            try relatedRecordCounts(chatID: "delete-me", in: container),
            [0, 0, 0, 0]
        )
        XCTAssertNil(try repository.suggestedReplyCache(chatID: "delete-me"))

        XCTAssertNotNil(try repository.chat(id: "keep-me"))
        XCTAssertEqual(try repository.messages(chatID: "keep-me").count, 1)
        XCTAssertEqual(
            try relatedRecordCounts(chatID: "keep-me", in: container),
            [1, 1, 1, 1]
        )
        XCTAssertNotNil(try repository.suggestedReplyCache(chatID: "keep-me"))
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
                title: name,
                previewText: message ?? "Imported conversation"
            )
        )
        if let message {
            container.mainContext.insert(
                ChatMessageRecord(
                    chatID: id,
                    senderKind: "other_participant",
                    text: message,
                    timeLabel: "10:50 AM",
                    sortIndex: 0
                )
            )
        }
    }

    private func insertRelatedRecords(chatID: String, into container: ModelContainer) {
        container.mainContext.insert(
            ChatContextRecord(
                chatID: chatID,
                currentInteractionGoal: "Reconnect",
                personaID: UUID()
            )
        )
        container.mainContext.insert(
            ChatMemoryRecord(
                chatID: chatID,
                value: ChatMemory(text: "Notes")
            )
        )
        container.mainContext.insert(
            ChatImportRecord(
                chatID: chatID,
                transcriptFingerprint: "fingerprint-\(chatID)",
                insertedMessageCount: 1,
                isDuplicate: false,
                requiresReview: false
            )
        )
        container.mainContext.insert(
            PersonaLearningReceiptRecord(
                personaID: UUID(),
                chatID: chatID,
                messageID: UUID()
            )
        )
    }

    private func makePendingImport(operationID: UUID) -> ChatImportRecord {
        ChatImportRecord(
            chatID: "chat", transcriptFingerprint: nil,
            insertedMessageCount: 1, isDuplicate: false, requiresReview: false,
            operationID: operationID, draftingInputStateRaw: DraftingInputState.pending.rawValue
        )
    }

    private func insertReplyCache(chatID: String, into container: ModelContainer) {
        container.mainContext.insert(
            SuggestedReplyCacheRecord(
                chatID: chatID,
                presentationLanguageIdentifier: "en",
                historySummary: "Summary",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: "fingerprint",
                repliesJSON: "[\"One\",\"Two\"]",
                inputFingerprint: "input",
                promptVersion: SuggestedReplyPrompt.version
            )
        )
    }

    private func relatedRecordCounts(chatID: String, in container: ModelContainer) throws -> [Int] {
        let chatContextRecords = try container.mainContext.fetch(
            FetchDescriptor<ChatContextRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let importRecords = try container.mainContext.fetch(
            FetchDescriptor<ChatImportRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let memoryRecords = try container.mainContext.fetch(
            FetchDescriptor<ChatMemoryRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let learningReceipts = try container.mainContext.fetch(
            FetchDescriptor<PersonaLearningReceiptRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        return [
            chatContextRecords.count,
            memoryRecords.count,
            importRecords.count,
            learningReceipts.count
        ]
    }

    private func provisionalAnalysis() -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: "Weekend Hike",
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: "Alex",
                    text: "Trail at eight?",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0
        )
    }

}
