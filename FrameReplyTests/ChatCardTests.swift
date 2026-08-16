import XCTest

@testable import FrameReply

@MainActor
final class ChatCardTests: XCTestCase {
    func testPersonaResolutionUsesAssignmentThenFallsBackToDefault() {
        let defaultPersona = makePersona(name: "Professional")
        let assignedPersona = makePersona(name: "Thoughtful")
        let context = ChatContextRecord(
            chatID: "assigned",
            currentInteractionGoal: "",
            personaID: assignedPersona.id
        )
        let personasByID = [
            defaultPersona.id: defaultPersona,
            assignedPersona.id: assignedPersona
        ]

        XCTAssertEqual(
            ChatsPresentation.persona(
                context: context,
                personasByID: personasByID,
                fallback: defaultPersona
            ),
            assignedPersona
        )
        XCTAssertEqual(
            ChatsPresentation.persona(
                context: nil,
                personasByID: personasByID,
                fallback: defaultPersona
            ),
            defaultPersona
        )
    }

    func testReviewBadgeReplacesPersonaBadge() {
        let persona = makePersona(name: "Thoughtful")
        let normalChat = makeChat(isProvisional: false)
        let reviewChat = makeChat(isProvisional: true)

        XCTAssertEqual(
            ChatsPresentation.badge(for: normalChat, persona: persona),
            .persona(persona)
        )
        XCTAssertEqual(
            ChatsPresentation.badge(for: reviewChat, persona: persona),
            .reviewImport
        )
    }

    func testSearchMatchesVisibleAndContextualChatInformation() {
        let persona = makePersona(name: "Thoughtful")
        let normalChat = makeChat(
            name: "Avery Chen",
            preview: "See you on Friday",
            isProvisional: false
        )
        let reviewChat = makeChat(isProvisional: true)

        XCTAssertTrue(
            ChatsPresentation.matches(
                query: "avery",
                chat: normalChat,
                persona: persona
            )
        )
        XCTAssertTrue(
            ChatsPresentation.matches(
                query: "friday",
                chat: normalChat,
                persona: persona
            )
        )
        XCTAssertTrue(
            ChatsPresentation.matches(
                query: "thought",
                chat: normalChat,
                persona: persona
            )
        )
        XCTAssertTrue(
            ChatsPresentation.matches(
                query: "review",
                chat: reviewChat,
                persona: persona
            )
        )
        XCTAssertFalse(
            ChatsPresentation.matches(
                query: "general",
                chat: normalChat,
                persona: persona
            )
        )
    }

    func testActivityDateStyleBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 24,
                    hour: 15,
                    minute: 30
                )
            )
        )

        XCTAssertEqual(
            ChatActivityDateFormatter.style(
                for: now,
                relativeTo: now,
                calendar: calendar
            ),
            .time
        )
        XCTAssertEqual(
            ChatActivityDateFormatter.style(
                for: try date(daysBefore: 3, now: now, calendar: calendar),
                relativeTo: now,
                calendar: calendar
            ),
            .weekday
        )
        XCTAssertEqual(
            ChatActivityDateFormatter.style(
                for: try date(daysBefore: 7, now: now, calendar: calendar),
                relativeTo: now,
                calendar: calendar
            ),
            .monthDay
        )
        XCTAssertEqual(
            ChatActivityDateFormatter.style(
                for: try XCTUnwrap(
                    calendar.date(
                        from: DateComponents(year: 2025, month: 12, day: 31)
                    )
                ),
                relativeTo: now,
                calendar: calendar
            ),
            .shortDate
        )
    }

    func testGroupProjectionUsesTruthfulFallbackSymbolAndAttributedPreview() {
        let record = ChatRecord(
            id: "group-chat",
            title: nil,
            previewText: "Trail at eight?",
            previewSenderKind: "group_participant",
            previewSenderName: "Alex",
            conversationKind: .group
        )
        let chat = Chat(record: record)

        XCTAssertEqual(chat.name, "Group Chat")
        XCTAssertEqual(chat.avatarSymbol, "person.2.fill")
        XCTAssertEqual(chat.conversationKind, .group)
        XCTAssertEqual(chat.preview, "Alex: Trail at eight?")

        record.previewSenderKind = "user"
        record.previewSenderName = nil
        XCTAssertEqual(record.displayPreview(), "You: Trail at eight?")

        record.previewSenderKind = "unknown"
        XCTAssertEqual(record.displayPreview(), "Unknown sender: Trail at eight?")
    }

    func testDirectProjectionAndMessageLabelsRemainUnchanged() {
        let record = ChatRecord(
            id: "direct-chat",
            title: "Alex",
            previewText: "Trail at eight?",
            previewSenderKind: "other_participant",
            previewSenderName: "Alex",
            conversationKind: .direct
        )
        let chat = Chat(record: record)
        let directMessage = ChatMessage(
            id: UUID(),
            sender: .otherParticipant,
            text: "Hi",
            timeLabel: "8:00"
        )
        let groupMessage = ChatMessage(
            id: UUID(),
            sender: .groupParticipant("Alex"),
            text: "Hi",
            timeLabel: "8:00"
        )

        XCTAssertEqual(chat.name, "Alex")
        XCTAssertNil(chat.avatarSymbol)
        XCTAssertEqual(chat.conversationKind, .direct)
        XCTAssertEqual(chat.preview, "Trail at eight?")
        XCTAssertNil(directMessage.groupParticipantName)
        XCTAssertEqual(groupMessage.groupParticipantName, "Alex")
    }

    func testHistorySearchMatchesGroupParticipantName() {
        let message = ChatMessage(
            id: UUID(),
            sender: .groupParticipant("Priya"),
            text: "The reservation is confirmed",
            timeLabel: "9:12 AM"
        )

        XCTAssertTrue(ChatHistoryPresentation.matches(query: "priya", message: message))
        XCTAssertTrue(ChatHistoryPresentation.matches(query: "reservation", message: message))
        XCTAssertTrue(ChatHistoryPresentation.matches(query: "9:12", message: message))
        XCTAssertFalse(ChatHistoryPresentation.matches(query: "alex", message: message))
        XCTAssertEqual(
            message.accessibilityDescription,
            "Sender Priya: The reservation is confirmed, 9:12 AM"
        )
    }

    private func makePersona(name: String) -> Persona {
        Persona(
            id: UUID(),
            name: name,
            summary: "",
            symbolName: "sparkles",
            accentKey: "primary",
            instructions: "",
            learningEnabled: true
        )
    }

    private func makeChat(
        name: String = "Avery",
        preview: String = "Latest message",
        isProvisional: Bool
    ) -> Chat {
        Chat(
            id: UUID().uuidString,
            name: name,
            preview: preview,
            avatarSymbol: nil,
            initials: "A",
            gradient: [FrameReplyColor.primary, FrameReplyColor.primaryContainer],
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            isProvisional: isProvisional
        )
    }

    private func date(
        daysBefore days: Int,
        now: Date,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: -days, to: now))
    }
}
