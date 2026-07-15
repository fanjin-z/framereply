import SwiftData
import XCTest

@testable import zeptly

@MainActor
final class ChatParticipantIdentityTests: XCTestCase {
    func testCopiedTranscriptAuthorsResolveAsOneDirectConversationAction() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let importOutcome = try repository.applyImport(
            analysis: copiedTranscriptAnalysis(),
            confirmedChatID: nil
        )

        XCTAssertEqual(try repository.chat(id: importOutcome.chatID)?.name, "Imported Chat")
        let outcome = try repository.resolveUnknownSenderLabels(
            chatID: importOutcome.chatID,
            selfLabel: "Test User"
        )

        XCTAssertEqual(outcome.resolvedUserCount, 4)
        XCTAssertEqual(outcome.resolvedOtherCount, 6)
        XCTAssertEqual(outcome.remainingUnknownCount, 0)
        XCTAssertTrue(outcome.renamedChat)

        let chat = try XCTUnwrap(repository.chat(id: importOutcome.chatID))
        XCTAssertEqual(chat.name, "Sample Contact")
        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertTrue(chat.isProvisional)

        let messages = try repository.messages(chatID: importOutcome.chatID)
        XCTAssertEqual(messages.filter { $0.senderKind == "user" }.count, 4)
        XCTAssertEqual(messages.filter { $0.senderKind == "other_participant" }.count, 6)
        XCTAssertEqual(Set(messages.compactMap(\.senderName)), ["Sample Contact"])
        XCTAssertEqual(
            try repository.selfAliases(chatID: importOutcome.chatID).map(\.displayLabel),
            [
                "Test User"
            ])
        let recognizedParticipantLabels =
            [chat.name] + (try repository.participantAliases(chatID: chat.id).map(\.displayLabel))
        XCTAssertEqual(
            Set(recognizedParticipantLabels.compactMap(ChatParticipantAlias.normalizedKey)),
            ["sample contact"]
        )
        XCTAssertFalse(
            recognizedParticipantLabels.compactMap(ChatParticipantAlias.normalizedKey)
                .contains("test user")
        )
    }

    func testInverseCopiedTranscriptSelectionRenamesChatToOtherAuthor() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let importOutcome = try repository.applyImport(
            analysis: copiedTranscriptAnalysis(),
            confirmedChatID: nil
        )

        let outcome = try repository.resolveUnknownSenderLabels(
            chatID: importOutcome.chatID,
            selfLabel: "Sample Contact"
        )

        XCTAssertEqual(outcome.resolvedUserCount, 6)
        XCTAssertEqual(outcome.resolvedOtherCount, 4)
        XCTAssertEqual(try repository.chat(id: importOutcome.chatID)?.name, "Test User")
    }

    func testRememberedAliasAppliesOnlyWithinSelectedChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let first = try repository.applyImport(
            analysis: copiedTranscriptAnalysis(),
            confirmedChatID: nil
        )
        try repository.resolveUnknownSenderLabels(chatID: first.chatID, selfLabel: "Test User")

        let laterAnalysis = directUnknownAnalysis(
            userText: "I will be back later.",
            otherText: "Sounds good.",
            matchedChatID: first.chatID
        )
        _ = try repository.applyImport(
            analysis: laterAnalysis,
            confirmedChatID: first.chatID
        )

        let laterMessages = try repository.messages(chatID: first.chatID).filter {
            $0.text == "I will be back later." || $0.text == "Sounds good."
        }
        XCTAssertEqual(
            laterMessages.first(where: { $0.text == "I will be back later." })?.senderKind,
            "user"
        )
        XCTAssertEqual(
            laterMessages.first(where: { $0.text == "Sounds good." })?.senderKind,
            "other_participant"
        )

        let otherChat = ChatRecord(
            id: "other-chat",
            name: "Other Chat",
            preview: "",
            conversationKind: .direct
        )
        container.mainContext.insert(otherChat)
        try container.mainContext.save()
        _ = try repository.applyImport(
            analysis: directUnknownAnalysis(
                userText: "A separate conversation.",
                otherText: "This should stay unresolved.",
                matchedChatID: "other-chat"
            ),
            confirmedChatID: "other-chat"
        )

        XCTAssertEqual(
            try repository.messages(chatID: "other-chat").filter { $0.senderKind == "unknown" }
                .count,
            2
        )
    }

    func testGroupResolutionPreservesParticipantsAndLeavesUnlabeledUnknown() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let analysis = ChatImportAnalysis(
            conversationTitle: "Weekend Group",
            messages: [
                unknownMessage(name: "Me", text: "I can join"),
                unknownMessage(name: "Alex", text: "Great"),
                unknownMessage(name: "Sam", text: "See you there"),
                unknownMessage(name: nil, text: "Unlabeled attachment caption")
            ],
            matchedChatID: nil,
            matchConfidence: 0,
            conversationKind: .group
        )
        let importOutcome = try repository.applyImport(
            analysis: analysis,
            confirmedChatID: nil
        )

        let outcome = try repository.resolveUnknownSenderLabels(
            chatID: importOutcome.chatID,
            selfLabel: "Me"
        )
        let messages = try repository.messages(chatID: importOutcome.chatID)

        XCTAssertEqual(outcome.resolvedUserCount, 1)
        XCTAssertEqual(outcome.resolvedOtherCount, 2)
        XCTAssertEqual(outcome.remainingUnknownCount, 1)
        XCTAssertFalse(outcome.renamedChat)
        XCTAssertEqual(
            Set(messages.filter { $0.senderKind == "group_participant" }.compactMap(\.senderName)),
            [
                "Alex", "Sam"
            ])
        XCTAssertEqual(
            messages.first(where: { $0.text.hasPrefix("Unlabeled") })?.senderKind, "unknown")
    }

    func testDestinationAliasResolvesProvisionalMessagesDuringMerge() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let target = ChatRecord(
            id: "target-chat",
            name: "Sample Contact",
            preview: "",
            conversationKind: .direct
        )
        container.mainContext.insert(target)
        container.mainContext.insert(
            ChatSelfAliasRecord(
                chatID: target.id,
                displayLabel: "Test User"
            )
        )
        try container.mainContext.save()

        let provisional = try repository.applyImport(
            analysis: directUnknownAnalysis(
                userText: "This message is mine after merging.",
                otherText: "This message belongs to the other participant.",
                matchedChatID: nil
            ),
            confirmedChatID: nil
        )
        try repository.mergeProvisionalChat(provisional.chatID, into: target.id)

        let messages = try repository.messages(chatID: target.id)
        XCTAssertEqual(
            messages.first(where: { $0.text == "This message is mine after merging." })?
                .senderKind,
            "user"
        )
        XCTAssertEqual(
            messages.first(where: {
                $0.text == "This message belongs to the other participant."
            })?.senderKind,
            "other_participant"
        )
        XCTAssertNil(try repository.chat(id: provisional.chatID))
    }

    func testManualMergeUnionsParticipantAliasesAndLearnsProvisionalName() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let target = ChatRecord(
            id: "merge-target",
            name: "Sarah Jenkins",
            preview: "",
            conversationKind: .direct
        )
        container.mainContext.insert(target)
        try container.mainContext.save()
        try repository.updateParticipantNames(
            chatID: target.id,
            displayName: target.name,
            aliases: [ChatParticipantAlias(displayLabel: "Sarah J.")]
        )

        let provisional = try repository.applyImport(
            analysis: ChatImportAnalysis(
                conversationTitle: "@sarah_work",
                messages: [
                    AnalyzedChatMessage(
                        sender: .otherParticipant,
                        senderName: "@sarah_work",
                        text: "Message from the renamed account",
                        timestampLabel: nil
                    )
                ],
                matchedChatID: nil,
                matchConfidence: 0,
                conversationKind: .direct,
                titleSource: .header
            ),
            confirmedChatID: nil
        )
        try repository.updateParticipantNames(
            chatID: provisional.chatID,
            displayName: "@sarah_work",
            aliases: [ChatParticipantAlias(displayLabel: "Sarah Chen")]
        )

        try repository.mergeProvisionalChat(provisional.chatID, into: target.id)

        XCTAssertEqual(
            Set(try repository.participantAliases(chatID: target.id).map(\.normalizedLabel)),
            ["sarah j.", "sarah chen", "@sarah_work"]
        )
        XCTAssertNil(try repository.chatContext(chatID: provisional.chatID))
    }

    func testAliasesNormalizeForgetAndDeleteWithChat() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let first = try repository.applyImport(
            analysis: directUnknownAnalysis(
                selfName: "Cafe\u{301}   User",
                userText: "One",
                otherText: "Two",
                matchedChatID: nil
            ),
            confirmedChatID: nil
        )

        try repository.resolveUnknownSenderLabels(
            chatID: first.chatID,
            selfLabel: "  Café\u{00A0}User "
        )
        XCTAssertEqual(try repository.selfAliases(chatID: first.chatID).count, 1)
        XCTAssertEqual(
            try repository.selfAliases(chatID: first.chatID).first?.displayLabel, "Café User")

        try repository.forgetImportedSelfLabels(chatID: first.chatID)
        XCTAssertTrue(try repository.selfAliases(chatID: first.chatID).isEmpty)

        container.mainContext.insert(
            ChatSelfAliasRecord(
                chatID: first.chatID,
                displayLabel: "Café User"
            )
        )
        try container.mainContext.save()
        try repository.deleteChat(id: first.chatID)
        XCTAssertTrue(try repository.selfAliases(chatID: first.chatID).isEmpty)
    }

    func testParticipantAliasJSONRoundTripsAndDefaultsEmpty() throws {
        let record = ChatContextRecord(
            chatID: "chat",
            currentInteractionGoal: "",
            personaID: UUID()
        )
        XCTAssertEqual(record.participantAliasesJSON, "[]")
        XCTAssertTrue(record.participantAliases.isEmpty)

        let alias = ChatParticipantAlias(
            id: UUID(),
            displayLabel: "@alex_92"
        )
        record.participantAliases = [alias]

        XCTAssertFalse(record.participantAliasesJSON.isEmpty)
        XCTAssertEqual(record.participantAliases, [alias])
    }

    func testParticipantNamesRoundTripDeduplicateAndRename() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "participant-names",
            name: "Sarah Jenkins",
            preview: "",
            conversationKind: .direct
        )
        container.mainContext.insert(chat)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try repository.updateParticipantNames(
                chatID: chat.id,
                displayName: "   ",
                aliases: []
            )
        ) { error in
            XCTAssertEqual(error as? ChatParticipantNameError, .emptyDisplayName)
        }

        try repository.updateParticipantNames(
            chatID: chat.id,
            displayName: "Sarah Chen",
            aliases: [
                ChatParticipantAlias(displayLabel: "  Café   Sarah "),
                ChatParticipantAlias(displayLabel: "cafe sarah"),
                ChatParticipantAlias(displayLabel: "Imported Chat")
            ]
        )

        XCTAssertEqual(try repository.chat(id: chat.id)?.name, "Sarah Chen")
        let aliases = try repository.participantAliases(chatID: chat.id)
        XCTAssertEqual(Set(aliases.map(\.normalizedLabel)), ["cafe sarah", "sarah jenkins"])
        XCTAssertEqual(
            aliases.first(where: { $0.normalizedLabel == "cafe sarah" })?.displayLabel,
            "Café Sarah"
        )

        XCTAssertFalse(try XCTUnwrap(repository.chatContext(chatID: chat.id))
            .participantAliasesJSON.isEmpty)
    }

    func testConfirmedExistingImportLearnsChangedName() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        let chat = ChatRecord(
            id: "known-participant",
            name: "Old Name",
            preview: "",
            conversationKind: .direct
        )
        container.mainContext.insert(chat)
        try container.mainContext.save()

        let confirmedAnalysis = ChatImportAnalysis(
            conversationTitle: "New Name",
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: "New Name",
                    text: "A confirmed message",
                    timestampLabel: nil
                )
            ],
            matchedChatID: chat.id,
            matchConfidence: 0.98,
            conversationKind: .direct,
            titleSource: .header
        )
        _ = try repository.applyImport(
            analysis: confirmedAnalysis,
            confirmedChatID: chat.id
        )

        XCTAssertEqual(
            try repository.participantAliases(chatID: chat.id).map(\.normalizedLabel),
            ["new name"]
        )

    }

    private func copiedTranscriptAnalysis() -> ChatImportAnalysis {
        let records: [(String, String)] = [
            ("Sample Contact", "Are you almost home?"),
            ("Test User", "I just arrived at Central Station."),
            ("Test User", "I fell asleep on the train."),
            ("Sample Contact", "Okay, take a cab home."),
            ("Sample Contact", "What would you like for lunch?"),
            ("Test User", "Could you bring me a coffee when you return?"),
            ("Sample Contact", "I will not be back until after four."),
            ("Test User", "No problem, never mind."),
            ("Sample Contact", "I will get you one tomorrow."),
            ("Sample Contact", "The demo portfolio is up again today.")
        ]
        return ChatImportAnalysis(
            conversationTitle: nil,
            messages: records.map { unknownMessage(name: $0.0, text: $0.1) },
            matchedChatID: nil,
            matchConfidence: 0,
            conversationKind: .direct
        )
    }

    private func directUnknownAnalysis(
        selfName: String = "Test User",
        userText: String,
        otherText: String,
        matchedChatID: String?
    ) -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: nil,
            messages: [
                unknownMessage(name: selfName, text: userText),
                unknownMessage(name: "Sample Contact", text: otherText)
            ],
            matchedChatID: matchedChatID,
            matchConfidence: matchedChatID == nil ? 0 : 0.99,
            conversationKind: .direct
        )
    }

    private func unknownMessage(name: String?, text: String) -> AnalyzedChatMessage {
        AnalyzedChatMessage(
            sender: .unknown,
            senderName: name,
            text: text,
            timestampLabel: nil,
            outerAuthorLabel: name,
            senderConfidence: 0,
            senderEvidence: .insufficient
        )
    }
}
