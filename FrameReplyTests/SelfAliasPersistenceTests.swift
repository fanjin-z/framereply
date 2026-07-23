import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class SelfAliasPersistenceTests: XCTestCase {
    func testStoreNameAndUnassociatedAliasPersistAcrossReload() throws {
        XCTAssertEqual(FrameReplyDataStore.configurationName, "FrameReplyChatsV1")

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            try repository.addSelfAlias(displayLabel: "  Alias   Alpha  ")

            XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])
        }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)

            XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])
            XCTAssertTrue(
                try container.mainContext.fetch(FetchDescriptor<ChatContextRecord>()).isEmpty)
        }
    }

    func testOneAliasCanBelongToMultipleContextsWithoutDuplicates() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try insertChat(id: "chat-delta", title: "Chat Delta", into: container)

        let first = try repository.addSelfAlias(
            displayLabel: "Alias Alpha",
            chatID: "chat-gamma"
        )
        let repeated = try repository.addSelfAlias(
            displayLabel: " alias alpha ",
            chatID: "chat-gamma"
        )
        let shared = try repository.addSelfAlias(
            displayLabel: "ALIAS ALPHA",
            chatID: "chat-delta"
        )

        XCTAssertEqual(try repository.selfAliases().count, 1)
        XCTAssertTrue(first === repeated)
        XCTAssertTrue(first === shared)
        try repository.renameChat(id: "chat-gamma", name: "Chat Gamma Renamed")
        XCTAssertEqual(try repository.selfAliases(chatID: "chat-gamma").count, 1)
        XCTAssertEqual(try repository.selfAliases(chatID: "chat-delta").count, 1)
    }

    func testSharedContextAssociationsPersistAcrossReload() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)
            try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
            try insertChat(id: "chat-delta", title: "Chat Delta", into: container)
            try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")
            try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-delta")
        }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)

            XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])
            XCTAssertEqual(
                try repository.selfAliases(chatID: "chat-gamma").map(\.displayLabel),
                ["Alias Alpha"]
            )
            XCTAssertEqual(
                try repository.selfAliases(chatID: "chat-delta").map(\.displayLabel),
                ["Alias Alpha"]
            )
            try repository.deleteChat(id: "chat-gamma")
        }

        do {
            let container = try FrameReplyDataStore.makeContainer(url: storeURL)
            let repository = ChatRepository(container: container)

            XCTAssertNil(try repository.chat(id: "chat-gamma"))
            XCTAssertTrue(try repository.selfAliases(chatID: "chat-gamma").isEmpty)
            XCTAssertEqual(
                try repository.selfAliases(chatID: "chat-delta").map(\.displayLabel),
                ["Alias Alpha"]
            )
            XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])
        }
    }

    func testChatDeletionDropsOnlyOwnedContextAndRetainsGlobalAlias() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(
            id: "chat-gamma",
            title: "Chat Gamma",
            message: "Synthetic message A",
            into: container
        )
        try insertChat(
            id: "chat-delta",
            title: "Chat Delta",
            message: "Synthetic message B",
            into: container
        )
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-delta")

        try repository.deleteChat(id: "chat-gamma")

        XCTAssertNil(try repository.chat(id: "chat-gamma"))
        XCTAssertTrue(try repository.selfAliases(chatID: "chat-gamma").isEmpty)
        XCTAssertEqual(
            try repository.selfAliases(chatID: "chat-delta").map(\.displayLabel),
            ["Alias Alpha"]
        )
        XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])

        try repository.deleteChat(id: "chat-delta")

        XCTAssertEqual(try repository.selfAliases().map(\.displayLabel), ["Alias Alpha"])
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ChatContextRecord>()).isEmpty
        )
    }

    func testRenameMergesNormalizedDuplicatesAndGlobalDeleteLeavesChatsAndMessages() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(
            id: "chat-gamma",
            title: "Chat Gamma",
            message: "Synthetic message A",
            into: container
        )
        try insertChat(
            id: "chat-delta",
            title: "Chat Delta",
            message: "Synthetic message B",
            into: container
        )
        let alpha = try repository.addSelfAlias(
            displayLabel: "Alias Alpha",
            chatID: "chat-gamma"
        )
        let beta = try repository.addSelfAlias(
            displayLabel: "Alias Beta",
            chatID: "chat-delta"
        )

        try repository.renameSelfAlias(alpha, displayLabel: "Alias Gamma")
        XCTAssertEqual(
            try repository.selfAliases(chatID: "chat-gamma").map(\.displayLabel),
            ["Alias Gamma"]
        )

        try repository.renameSelfAlias(beta, displayLabel: " alias gamma ")

        let aliases = try repository.selfAliases()
        XCTAssertEqual(aliases.map(\.displayLabel), ["Alias Gamma"])
        XCTAssertEqual(try repository.selfAliases(chatID: "chat-gamma").count, 1)
        XCTAssertEqual(try repository.selfAliases(chatID: "chat-delta").count, 1)

        try repository.deleteSelfAlias(try XCTUnwrap(aliases.first))

        XCTAssertTrue(try repository.selfAliases().isEmpty)
        XCTAssertTrue(try repository.selfAliases(chatID: "chat-gamma").isEmpty)
        XCTAssertTrue(try repository.selfAliases(chatID: "chat-delta").isEmpty)
        XCTAssertNotNil(try repository.chat(id: "chat-gamma"))
        XCTAssertNotNil(try repository.chat(id: "chat-delta"))
        XCTAssertEqual(try repository.messages(chatID: "chat-gamma").count, 1)
        XCTAssertEqual(try repository.messages(chatID: "chat-delta").count, 1)
    }

    func testForgetClearsOnlyOneContextAndLeavesGlobalAlias() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try insertChat(id: "chat-delta", title: "Chat Delta", into: container)
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-delta")

        try repository.forgetImportedSelfLabels(chatID: "chat-gamma")

        XCTAssertTrue(try repository.selfAliases(chatID: "chat-gamma").isEmpty)
        XCTAssertEqual(try repository.selfAliases(chatID: "chat-delta").count, 1)
        XCTAssertEqual(try repository.selfAliases().count, 1)
    }

    func testOnlySameChatAliasAutomaticallyResolvesAnImport() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try insertChat(id: "chat-delta", title: "Chat Delta", into: container)
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")
        try repository.addSelfAlias(displayLabel: "Alias Unused")

        _ = try repository.applyImport(
            analysis: unknownAnalysis(
                title: "Chat Gamma",
                senderName: "Alias Alpha",
                message: "Synthetic message A",
                matchedChatID: "chat-gamma"
            ),
            confirmedChatID: "chat-gamma"
        )
        _ = try repository.applyImport(
            analysis: unknownAnalysis(
                title: "Chat Delta",
                senderName: "Alias Alpha",
                message: "Synthetic message B",
                matchedChatID: "chat-delta"
            ),
            confirmedChatID: "chat-delta"
        )

        XCTAssertEqual(
            try repository.messages(chatID: "chat-gamma").last?.senderKind,
            "user"
        )
        XCTAssertEqual(
            try repository.messages(chatID: "chat-delta").last?.senderKind,
            "unknown"
        )
        let candidate = try XCTUnwrap(
            repository.matchCandidates().first { $0.id == "chat-gamma" }
        )
        XCTAssertFalse(
            candidate.participantAliases.contains {
                IdentityLabelPolicy.normalizedKey($0)
                    == IdentityLabelPolicy.normalizedKey("Alias Alpha")
            }
        )
    }

    func testPreviouslyUsedAliasCreatesNonblockingProvisionalInterpretation() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try repository.addSelfAlias(
            displayLabel: "Alias Alpha",
            chatID: "chat-gamma"
        )

        let outcome = try repository.applyImport(
            analysis: twoAuthorUnknownAnalysis(),
            confirmedChatID: nil
        )

        XCTAssertFalse(outcome.reviewRequired)
        XCTAssertEqual(outcome.chatTitle, "Contact Beta")

        let provisionalChat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertTrue(provisionalChat.requiresImportIdentityReview)
        XCTAssertNil(provisionalChat.title)

        let messages = try repository.messages(chatID: outcome.chatID)
        XCTAssertEqual(messages.map(\.senderKind), ["unknown", "unknown"])
        let interpretation = try XCTUnwrap(
            repository.provisionalIdentityInterpretation(chatID: outcome.chatID)
        )
        XCTAssertEqual(interpretation.selfDisplayLabel, "Alias Alpha")
        XCTAssertEqual(interpretation.counterpartDisplayLabel, "Contact Beta")
        XCTAssertEqual(interpretation.displayTitle, "Contact Beta")
        XCTAssertEqual(
            messages.map { interpretation.senderKind(for: $0) },
            ["user", "other_participant"]
        )
        XCTAssertEqual(
            Chat(record: provisionalChat, provisionalIdentity: interpretation).name,
            "Contact Beta"
        )

        let candidate = try XCTUnwrap(
            repository.matchCandidates().first { $0.id == outcome.chatID }
        )
        XCTAssertNil(candidate.title)
        XCTAssertFalse(
            candidate.participantAliases.contains {
                IdentityLabelPolicy.normalizedKey($0)
                    == IdentityLabelPolicy.normalizedKey("Alias Alpha")
            }
        )

        let resolution = try repository.resolveUnknownSenderLabels(
            chatID: outcome.chatID,
            selfLabel: "Alias Alpha"
        )
        XCTAssertEqual(resolution.resolvedUserCount, 1)
        XCTAssertEqual(resolution.resolvedOtherCount, 1)
        XCTAssertEqual(resolution.remainingUnknownCount, 0)

        let identityResolvedChat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertTrue(identityResolvedChat.requiresImportIdentityReview)
        XCTAssertTrue(identityResolvedChat.isProvisional)
        XCTAssertEqual(identityResolvedChat.title, "Contact Beta")
        XCTAssertEqual(
            try repository.messages(chatID: outcome.chatID).map(\.senderKind),
            ["user", "other_participant"]
        )
        XCTAssertEqual(
            try repository.selfAliases(chatID: outcome.chatID).map(\.displayLabel),
            ["Alias Alpha"]
        )
        XCTAssertTrue(
            try XCTUnwrap(repository.importRecord(id: outcome.importID)).requiresReview
        )

        try repository.confirmProvisionalChat(
            chatID: outcome.chatID,
            name: "Contact Beta"
        )

        let confirmedChat = try XCTUnwrap(repository.chat(id: outcome.chatID))
        XCTAssertFalse(confirmedChat.requiresImportIdentityReview)
        XCTAssertFalse(confirmedChat.isProvisional)
        XCTAssertEqual(confirmedChat.title, "Contact Beta")
        XCTAssertFalse(
            try XCTUnwrap(repository.importRecord(id: outcome.importID)).requiresReview
        )
    }

    func testUnassociatedOrAmbiguousAliasesDoNotCreateProvisionalInterpretation() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.addSelfAlias(displayLabel: "Alias Alpha")

        let unassociated = try repository.applyImport(
            analysis: twoAuthorUnknownAnalysis(),
            confirmedChatID: nil
        )
        XCTAssertTrue(unassociated.reviewRequired)
        XCTAssertNil(
            try repository.provisionalIdentityInterpretation(chatID: unassociated.chatID)
        )

        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try insertChat(id: "chat-delta", title: "Chat Delta", into: container)
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")
        try repository.addSelfAlias(displayLabel: "Contact Beta", chatID: "chat-delta")

        let ambiguous = try repository.applyImport(
            analysis: twoAuthorUnknownAnalysis(),
            confirmedChatID: nil
        )
        XCTAssertTrue(ambiguous.reviewRequired)
        XCTAssertNil(
            try repository.provisionalIdentityInterpretation(chatID: ambiguous.chatID)
        )
    }

    func testProvisionalInterpretationRejectsGroupAndIncompleteSenderSets() {
        let groupChat = ChatRecord(
            id: "chat-gamma",
            title: nil,
            previewText: "Synthetic message B",
            conversationKind: .group,
            isProvisional: true
        )
        let directChat = ChatRecord(
            id: "chat-delta",
            title: nil,
            previewText: "Synthetic message B",
            conversationKind: .direct,
            isProvisional: true
        )
        let labeledMessages = [
            ChatMessageRecord(
                chatID: "chat-gamma",
                senderKind: "unknown",
                senderName: "Alias Alpha",
                text: "Synthetic message A",
                timeLabel: "",
                sortIndex: 0
            ),
            ChatMessageRecord(
                chatID: "chat-gamma",
                senderKind: "unknown",
                senderName: "Contact Beta",
                text: "Synthetic message B",
                timeLabel: "",
                sortIndex: 1
            )
        ]

        XCTAssertNil(
            ProvisionalIdentityResolver.resolve(
                chat: groupChat,
                messages: labeledMessages,
                previouslyUsedSelfAliasLabels: ["Alias Alpha"]
            )
        )

        let unknownKindChat = ChatRecord(
            id: "chat-unknown-kind",
            title: nil,
            previewText: "Synthetic message B",
            conversationKind: .unknown,
            isProvisional: true
        )
        XCTAssertNil(
            ProvisionalIdentityResolver.resolve(
                chat: unknownKindChat,
                messages: labeledMessages,
                previouslyUsedSelfAliasLabels: ["Alias Alpha"]
            )
        )

        let incompleteMessages = [
            ChatMessageRecord(
                chatID: "chat-delta",
                senderKind: "unknown",
                senderName: "Alias Alpha",
                text: "Synthetic message A",
                timeLabel: "",
                sortIndex: 0
            ),
            ChatMessageRecord(
                chatID: "chat-delta",
                senderKind: "unknown",
                senderName: nil,
                text: "Synthetic message B",
                timeLabel: "",
                sortIndex: 1
            )
        ]
        XCTAssertNil(
            ProvisionalIdentityResolver.resolve(
                chat: directChat,
                messages: incompleteMessages,
                previouslyUsedSelfAliasLabels: ["Alias Alpha"]
            )
        )
    }

    func testMergeUnionsAliasesAndDeletesProvisionalLearningReceipts() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try insertChat(id: "chat-gamma", title: "Chat Gamma", into: container)
        try repository.addSelfAlias(displayLabel: "Alias Alpha", chatID: "chat-gamma")

        let provisional = try repository.applyImport(
            analysis: ChatImportAnalysis(
                conversationTitle: "Chat Delta",
                messages: [
                    AnalyzedChatMessage(
                        sender: .otherParticipant,
                        senderName: "Contact Beta",
                        text: "Synthetic message A",
                        timestampLabel: nil
                    )
                ],
                matchedChatID: nil,
                matchConfidence: 0,
                conversationKind: .direct
            ),
            confirmedChatID: nil
        )
        try repository.addSelfAlias(
            displayLabel: "Alias Beta",
            chatID: provisional.chatID
        )
        let provisionalMessage = try XCTUnwrap(
            repository.messages(chatID: provisional.chatID).first
        )
        container.mainContext.insert(
            PersonaLearningReceiptRecord(
                personaID: UUID(),
                chatID: provisional.chatID,
                messageID: provisionalMessage.id
            )
        )
        container.mainContext.insert(
            ChatMemoryRecord(
                chatID: provisional.chatID,
                value: ChatMemory(text: "Synthetic memory A")
            )
        )
        container.mainContext.insert(
            SuggestedReplyCacheRecord(
                chatID: provisional.chatID,
                presentationLanguageIdentifier: "en",
                historySummary: "Synthetic summary A",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: "synthetic-prefix-a",
                repliesJSON: "[\"Synthetic reply A\"]",
                inputFingerprint: "synthetic-input-a",
                promptVersion: SuggestedReplyPrompt.version
            )
        )
        try container.mainContext.save()

        try repository.mergeProvisionalChat(provisional.chatID, into: "chat-gamma")
        let provisionalChatID = provisional.chatID

        XCTAssertNil(try repository.chat(id: provisionalChatID))
        XCTAssertNil(try repository.chatContext(chatID: provisionalChatID))
        XCTAssertTrue(try repository.messages(chatID: provisionalChatID).isEmpty)
        XCTAssertTrue(try repository.chatMemories(chatID: provisionalChatID).isEmpty)
        XCTAssertNil(try repository.suggestedReplyCache(chatID: provisionalChatID))
        XCTAssertEqual(
            Set(try repository.selfAliases(chatID: "chat-gamma").map(\.displayLabel)),
            ["Alias Alpha", "Alias Beta"]
        )
        XCTAssertTrue(
            try container.mainContext.fetch(
                FetchDescriptor<PersonaLearningReceiptRecord>(
                    predicate: #Predicate { $0.chatID == provisionalChatID }
                )
            ).isEmpty
        )
        XCTAssertTrue(
            try container.mainContext.fetch(
                FetchDescriptor<ChatImportRecord>(
                    predicate: #Predicate { $0.chatID == provisionalChatID }
                )
            ).isEmpty
        )
        let targetChatID = "chat-gamma"
        XCTAssertEqual(
            try container.mainContext.fetch(
                FetchDescriptor<ChatImportRecord>(
                    predicate: #Predicate { $0.chatID == targetChatID }
                )
            ).count,
            1
        )
    }

    func testFallbackIsDisplayOnlyAndKeepRequiresSenderResolution() throws {
        XCTAssertNil(IdentityLabelPolicy.displayLabel("Imported Chat"))
        for localization in Bundle.main.localizations where localization != "Base" {
            let locale = Locale(identifier: localization)
            let fallback = AppStrings.resolve(AppStrings.Chat.titleFallback, locale: locale)
            XCTAssertNil(IdentityLabelPolicy.displayLabel(fallback, locale: locale))
        }
        XCTAssertFalse(
            ImportReviewReadiness.canKeep(
                name: "Chat Gamma",
                hasNamedUnresolvedSenders: true
            )
        )
        XCTAssertFalse(
            ImportReviewReadiness.canKeep(
                name: "Imported Chat",
                hasNamedUnresolvedSenders: false
            )
        )
        XCTAssertTrue(
            ImportReviewReadiness.canKeep(
                name: "Chat Gamma",
                hasNamedUnresolvedSenders: false
            )
        )

        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        XCTAssertThrowsError(try repository.addSelfAlias(displayLabel: "Imported Chat"))

        let outcome = try repository.applyImport(
            analysis: unknownAnalysis(
                title: "Imported Chat",
                senderName: "Alias Alpha",
                message: "Synthetic message A",
                matchedChatID: nil
            ),
            confirmedChatID: nil
        )
        XCTAssertNil(try repository.chat(id: outcome.chatID)?.title)
        XCTAssertThrowsError(
            try repository.confirmProvisionalChat(
                chatID: outcome.chatID,
                name: "Chat Gamma"
            )
        ) { error in
            XCTAssertEqual(error as? ChatImportReviewError, .senderIdentityRequired)
        }
    }

    private func insertChat(
        id: String,
        title: String,
        message: String? = nil,
        into container: ModelContainer
    ) throws {
        container.mainContext.insert(
            ChatRecord(
                id: id,
                title: title,
                previewText: message,
                conversationKind: .direct
            )
        )
        if let message {
            container.mainContext.insert(
                ChatMessageRecord(
                    chatID: id,
                    senderKind: "other_participant",
                    text: message,
                    timeLabel: "",
                    sortIndex: 0
                )
            )
        }
        try container.mainContext.save()
    }

    private func unknownAnalysis(
        title: String,
        senderName: String,
        message: String,
        matchedChatID: String?
    ) -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: title,
            messages: [
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: senderName,
                    text: message,
                    timestampLabel: nil
                )
            ],
            matchedChatID: matchedChatID,
            matchConfidence: 0.99,
            conversationKind: .direct
        )
    }

    private func twoAuthorUnknownAnalysis() -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: nil,
            messages: [
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Alias Alpha",
                    text: "Synthetic message A",
                    timestampLabel: nil
                ),
                AnalyzedChatMessage(
                    sender: .unknown,
                    senderName: "Contact Beta",
                    text: "Synthetic message B",
                    timestampLabel: nil
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0,
            conversationKind: .direct,
            titleSource: .unavailable
        )
    }
}
