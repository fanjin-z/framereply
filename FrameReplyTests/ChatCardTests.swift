import XCTest

@testable import FrameReply

@MainActor
final class ChatCardTests: XCTestCase {
    func testChatProjectionCarriesActivityDate() {
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let record = ChatRecord(
            id: "activity",
            title: "Avery",
            previewText: "Latest message",
            updatedAt: updatedAt
        )

        let chat = Chat(record: record)

        XCTAssertEqual(chat.updatedAt, updatedAt)
        XCTAssertEqual(chat.preview, "Latest message")
    }

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

    func testActivityDateTextIsLocalized() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
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

        let text = ChatActivityDateFormatter.text(
            for: date,
            relativeTo: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("3:30"))
    }

    private func makePersona(name: String) -> Persona {
        Persona(
            id: UUID(),
            name: name,
            summary: "",
            symbolName: "sparkles",
            accentKey: "primary",
            instructions: "",
            learningEnabled: true,
            sampleCount: 0
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
