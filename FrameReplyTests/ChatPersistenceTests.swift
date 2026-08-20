import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class ChatPersistenceTests: XCTestCase {
    func testApplyImportRejectsNoMessagesBeforeAnyMutation() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let originalDate = Date(timeIntervalSince1970: 1_000)
        let chat = ChatRecord(
            id: "existing-chat",
            title: "Alice",
            previewText: "Original preview",
            conversationKind: .direct,
            updatedAt: originalDate
        )
        container.mainContext.insert(chat)
        try container.mainContext.save()
        let analysis = ChatImportAnalysis(
            extractionStatus: .noMessages,
            conversationTitle: nil,
            messages: [],
            matchedChatID: nil,
            matchConfidence: 0,
            conversationKind: .unknown,
            titleSource: .unavailable,
            userIdentification: .unobservable
        )

        XCTAssertThrowsError(
            try repository.applyImport(
                analysis: analysis,
                confirmedChatID: chat.id
            )
        ) { error in
            XCTAssertEqual(error as? ChatImportPersistenceError, .noMessages)
        }

        XCTAssertEqual(chat.title, "Alice")
        XCTAssertEqual(chat.previewText, "Original preview")
        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertEqual(chat.updatedAt, originalDate)
        XCTAssertTrue(try repository.messages(chatID: chat.id).isEmpty)
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ChatContextRecord>()).isEmpty
        )
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ChatImportRecord>()).isEmpty
        )
    }

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

    func testGroupImportCanonicalizesSendersAndRefreshesPreviewAfterReview() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let analysis = ChatImportAnalysis(
            conversationTitle: nil,
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: "Alex",
                    text: "I can bring snacks",
                    timestampLabel: "8:00 PM"
                ),
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Priya",
                    text: "What time should we meet?",
                    timestampLabel: "8:01 PM"
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0,
            conversationKind: .group,
            titleSource: .unavailable
        )

        let outcome = try repository.applyImport(analysis: analysis, confirmedChatID: nil)
        let chat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        let messages = try repository.messages(chatID: outcome.chatID)

        XCTAssertEqual(chat.conversationKind, .group)
        XCTAssertNil(chat.title)
        XCTAssertEqual(chat.displayTitle(), "Group Chat")
        XCTAssertEqual(messages.map(\.senderKind), ["group_participant", "unknown"])
        XCTAssertEqual(messages.first?.senderName, "Alex")
        XCTAssertEqual(chat.previewText, "What time should we meet?")
        XCTAssertEqual(chat.previewSenderKind, "unknown")
        XCTAssertEqual(chat.previewSenderName, "Priya")
        XCTAssertTrue(outcome.reviewRequired)

        try repository.resolveUnknownSender(
            messageID: try XCTUnwrap(messages.last?.id),
            as: .groupParticipant,
            participantName: "Priya"
        )
        XCTAssertEqual(messages.last?.senderKind, "group_participant")
        XCTAssertEqual(chat.previewSenderKind, "group_participant")
        XCTAssertEqual(chat.previewSenderName, "Priya")
        try repository.confirmProvisionalChat(chatID: chat.id, name: "Group Chat")

        XCTAssertNil(chat.title)
        XCTAssertEqual(chat.displayTitle(), "Group Chat")
        XCTAssertFalse(chat.requiresImportIdentityReview)
    }

    func testGroupSupportMigrationBackfillsPreviewAndCanonicalizesMalformedSenders() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "legacy-group",
            title: nil,
            previewText: "Latest",
            conversationKind: .group
        )
        let previewOnlyChat = ChatRecord(
            id: "legacy-preview-only",
            title: "Archived chat",
            previewText: "Preserved denormalized preview",
            conversationKind: .direct
        )
        let named = ChatMessageRecord(
            chatID: chat.id,
            senderKind: "other_participant",
            senderName: "Alex",
            text: "Earlier",
            timeLabel: "8:00 PM",
            sortIndex: 0
        )
        let malformed = ChatMessageRecord(
            chatID: chat.id,
            senderKind: "alien_sender",
            senderName: "Mystery label",
            text: "Latest",
            timeLabel: "8:01 PM",
            sortIndex: 1
        )
        container.mainContext.insert(chat)
        container.mainContext.insert(previewOnlyChat)
        container.mainContext.insert(named)
        container.mainContext.insert(malformed)
        try container.mainContext.save()

        try repository.seedIfNeeded()
        try repository.seedIfNeeded()

        XCTAssertEqual(named.senderKind, "group_participant")
        XCTAssertEqual(named.senderName, "Alex")
        XCTAssertEqual(malformed.senderKind, "unknown")
        XCTAssertEqual(malformed.senderName, "Mystery label")
        XCTAssertEqual(chat.previewText, "Latest")
        XCTAssertEqual(chat.previewSenderKind, "unknown")
        XCTAssertEqual(chat.previewSenderName, "Mystery label")
        XCTAssertEqual(chat.displayPreview(), "Mystery label: Latest")
        XCTAssertEqual(previewOnlyChat.previewText, "Preserved denormalized preview")
        XCTAssertNil(previewOnlyChat.previewSenderKind)
    }

    func testStrongImportAndExplicitMergePromoteDirectChatsToGroup() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let direct = ChatRecord(
            id: "direct-chat",
            title: "Alex",
            previewText: nil,
            conversationKind: .direct
        )
        container.mainContext.insert(direct)
        try container.mainContext.save()
        let groupAnalysis = ChatImportAnalysis(
            conversationTitle: "Alex and Friends",
            messages: [
                AnalyzedChatMessage(
                    sender: .groupParticipant,
                    senderName: "Alex",
                    text: "Hello everyone",
                    timestampLabel: nil
                )
            ],
            matchedChatID: "direct-chat",
            matchConfidence: 0.99,
            conversationKind: .group,
            titleSource: .header
        )

        let promoted = try repository.applyImport(
            analysis: groupAnalysis,
            confirmedChatID: direct.id
        )
        XCTAssertEqual(promoted.chatID, direct.id)
        XCTAssertFalse(promoted.reviewRequired)
        XCTAssertEqual(direct.conversationKind, .group)
        XCTAssertEqual(direct.title, "Alex and Friends")
        XCTAssertTrue(direct.requiresImportReview)
        XCTAssertEqual(direct.importReviewState?.hasKindReview, true)

        let secondDirect = ChatRecord(
            id: "second-direct",
            title: "Taylor",
            previewText: nil,
            conversationKind: .direct
        )
        container.mainContext.insert(secondDirect)
        try container.mainContext.save()
        let provisional = try repository.applyImport(
            analysis: groupAnalysis,
            confirmedChatID: nil
        )
        let groupMemory = ChatMemoryRecord(
            chatID: provisional.chatID,
            value: ChatMemory(
                text: "Alex confirmed the team check-in",
                origin: .ai,
                certainty: .aiInferred
            )
        )
        container.mainContext.insert(groupMemory)
        try container.mainContext.save()
        try repository.mergeProvisionalChat(provisional.chatID, into: secondDirect.id)
        XCTAssertNil(try repository.chat(id: provisional.chatID))
        XCTAssertEqual(secondDirect.conversationKind, .group)
        XCTAssertEqual(secondDirect.title, "Alex and Friends")
        XCTAssertEqual(groupMemory.chatID, secondDirect.id)
        XCTAssertEqual(groupMemory.status, ChatMemoryStatus.active.rawValue)
    }

    func testInferenceOnlyGroupSuggestionDoesNotMutateDirectChat() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "ambiguous-direct",
            title: "Alex",
            previewText: nil,
            conversationKind: .direct
        )
        container.mainContext.insert(chat)
        try container.mainContext.save()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Alex",
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: "Alex",
                    text: "Ambiguous snippet",
                    timestampLabel: nil
                )
            ],
            matchedChatID: chat.id,
            matchConfidence: 0.99,
            conversationKind: .direct,
            conversationKindEvidence: .groupSuspectedWithoutStructuralProof,
            titleSource: .participantLabel
        )

        let outcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: chat.id
        )

        XCTAssertFalse(outcome.reviewRequired)
        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertEqual(chat.importReviewState?.hasKindReview, true)
        XCTAssertTrue(chat.requiresImportReview)

        try repository.confirmConversationKind(chatID: chat.id)
        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertFalse(chat.requiresImportReview)
    }

    func testNotShownResolutionDoesNotConfirmImportAndPreservesExistingGroup() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "not-shown",
            title: "Alex",
            previewText: "Second",
            conversationKind: .direct,
            isProvisional: true
        )
        let context = ChatContextRecord(
            chatID: chat.id,
            currentInteractionGoal: "",
            personaID: UUID()
        )
        let messages = [
            ChatMessageRecord(
                chatID: chat.id,
                senderKind: "unknown",
                senderName: "Alex",
                text: "First",
                timeLabel: "8:00",
                sortIndex: 0
            ),
            ChatMessageRecord(
                chatID: chat.id,
                senderKind: "unknown",
                senderName: "Taylor",
                text: "Second",
                timeLabel: "8:01",
                sortIndex: 1
            )
        ]
        container.mainContext.insert(chat)
        container.mainContext.insert(context)
        messages.forEach(container.mainContext.insert)
        try container.mainContext.save()

        try repository.resolveUnknownSenderLabelsAsGroup(chatID: chat.id)

        XCTAssertEqual(chat.conversationKind, .group)
        XCTAssertNil(chat.title)
        XCTAssertEqual(
            messages.map(\.senderKind),
            [
                "group_participant", "group_participant"
            ])
        XCTAssertEqual(messages.map(\.senderName), ["Alex", "Taylor"])
        XCTAssertEqual(chat.previewSenderKind, "group_participant")
        XCTAssertEqual(chat.previewSenderName, "Taylor")
        XCTAssertTrue(chat.requiresImportIdentityReview)
        XCTAssertEqual(chat.importReviewState?.identityStatus, .needsReview)

        let existingGroup = ChatRecord(
            id: "existing-group-not-shown",
            title: "Project Team",
            previewText: "Status update",
            conversationKind: .group,
            isProvisional: true
        )
        let groupMessage = ChatMessageRecord(
            chatID: existingGroup.id,
            senderKind: "unknown",
            senderName: "Jordan",
            text: "Status update",
            timeLabel: "8:02",
            sortIndex: 0
        )
        container.mainContext.insert(existingGroup)
        container.mainContext.insert(groupMessage)
        try container.mainContext.save()

        try repository.resolveUnknownSenderLabelsAsGroup(chatID: existingGroup.id)

        XCTAssertEqual(existingGroup.conversationKind, .group)
        XCTAssertEqual(existingGroup.title, "Project Team")
        XCTAssertEqual(groupMessage.senderKind, "group_participant")
        XCTAssertEqual(groupMessage.senderName, "Jordan")
        XCTAssertEqual(existingGroup.previewSenderKind, "group_participant")
        XCTAssertEqual(existingGroup.previewSenderName, "Jordan")
        XCTAssertTrue(existingGroup.requiresImportIdentityReview)
        XCTAssertEqual(existingGroup.importReviewState?.identityStatus, .needsReview)
    }

    func testManualReclassificationPreservesContextAndRawNamesWhileRefreshingDerivedState()
        throws
    {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "reclassify-chat",
            title: "Alex",
            previewText: "Latest",
            previewSenderKind: "unknown",
            previewSenderName: "Taylor",
            conversationKind: .direct
        )
        let context = ChatContextRecord(
            chatID: chat.id,
            currentInteractionGoal: "Choose a time",
            personaID: UUID()
        )
        context.participantAliases = [ChatParticipantAlias(displayLabel: "Alex A.")]
        let alex = ChatMessageRecord(
            chatID: chat.id,
            senderKind: "other_participant",
            senderName: nil,
            text: "Earlier",
            timeLabel: "8:00 PM",
            sortIndex: 0
        )
        let taylor = ChatMessageRecord(
            chatID: chat.id,
            senderKind: "unknown",
            senderName: "Taylor",
            text: "Latest",
            timeLabel: "8:01 PM",
            sortIndex: 1
        )
        let aiMemory = ChatMemoryRecord(
            chatID: chat.id,
            value: ChatMemory(
                text: "AI inference",
                origin: .ai,
                certainty: .aiInferred
            )
        )
        let userMemory = ChatMemoryRecord(
            chatID: chat.id,
            value: ChatMemory(text: "User note")
        )
        let importRecord = ChatImportRecord(
            chatID: chat.id,
            transcriptFingerprint: "old-fingerprint",
            insertedMessageCount: 2,
            isDuplicate: false,
            requiresReview: true
        )
        container.mainContext.insert(chat)
        container.mainContext.insert(context)
        container.mainContext.insert(alex)
        container.mainContext.insert(taylor)
        container.mainContext.insert(aiMemory)
        container.mainContext.insert(userMemory)
        container.mainContext.insert(importRecord)
        insertReplyCache(chatID: chat.id, into: container)
        try container.mainContext.save()

        try repository.reclassifyConversation(chatID: chat.id, to: .group)

        XCTAssertEqual(chat.conversationKind, .group)
        XCTAssertNil(chat.title)
        XCTAssertEqual(alex.senderKind, "group_participant")
        XCTAssertEqual(alex.senderName, "Alex")
        XCTAssertEqual(taylor.senderKind, "unknown")
        XCTAssertEqual(taylor.senderName, "Taylor")
        XCTAssertEqual(chat.previewSenderKind, "unknown")
        XCTAssertEqual(chat.previewSenderName, "Taylor")
        XCTAssertEqual(aiMemory.status, ChatMemoryStatus.active.rawValue)
        XCTAssertEqual(aiMemory.text, "Alex: AI inference")
        XCTAssertEqual(userMemory.status, ChatMemoryStatus.active.rawValue)
        XCTAssertNil(try repository.suggestedReplyCache(chatID: chat.id))
        XCTAssertNotEqual(importRecord.transcriptFingerprint, "old-fingerprint")
        XCTAssertEqual(context.currentInteractionGoal, "Choose a time")

        try repository.reclassifyConversation(
            chatID: chat.id,
            to: .direct,
            directDisplayName: "Morgan"
        )

        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertEqual(chat.title, "Morgan")
        XCTAssertEqual(alex.senderKind, "other_participant")
        XCTAssertEqual(alex.senderName, "Alex")
        XCTAssertEqual(taylor.senderKind, "other_participant")
        XCTAssertEqual(taylor.senderName, "Taylor")
        XCTAssertEqual(chat.previewSenderKind, "other_participant")
        XCTAssertEqual(chat.previewSenderName, "Taylor")
        XCTAssertEqual(aiMemory.status, ChatMemoryStatus.active.rawValue)
        XCTAssertEqual(aiMemory.text, "Alex: AI inference")
        XCTAssertEqual(context.currentInteractionGoal, "Choose a time")

        try repository.reclassifyConversation(chatID: chat.id, to: .group)
        XCTAssertEqual(aiMemory.status, ChatMemoryStatus.active.rawValue)
        XCTAssertEqual(aiMemory.text, "Alex: AI inference")
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
            userIdentification: .unobservable
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
            [0, 0, 0]
        )
        XCTAssertNil(try repository.suggestedReplyCache(chatID: "delete-me"))

        XCTAssertNotNil(try repository.chat(id: "keep-me"))
        XCTAssertEqual(try repository.messages(chatID: "keep-me").count, 1)
        XCTAssertEqual(
            try relatedRecordCounts(chatID: "keep-me", in: container),
            [1, 1, 1]
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
                appLanguage: "en",
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
        return [
            chatContextRecords.count,
            memoryRecords.count,
            importRecords.count
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
