import SwiftUI
import XCTest

@testable import FrameReply

final class ShortcutIntentConfigurationTests: XCTestCase {
    func testEndToEndIntentsAskForContextByDefault() {
        XCTAssertTrue(SuggestRepliesFromChatImagesIntent().askForContext)
        XCTAssertTrue(SuggestRepliesFromChatTextIntent().askForContext)
    }

    func testMaintainedReplySelectionIntentsStayInTheCurrentApp() {
        XCTAssertTrue(SuggestRepliesFromChatImagesIntent.isDiscoverable)
        XCTAssertTrue(SuggestRepliesFromChatTextIntent.isDiscoverable)
        XCTAssertFalse(SuggestRepliesFromChatImagesIntent.openAppWhenRun)
        XCTAssertFalse(SuggestRepliesFromChatTextIntent.openAppWhenRun)
    }

    func testSnippetIntentsAreNotDiscoverable() {
        XCTAssertFalse(ShortcutRepliesConfirmationSnippetIntent.isDiscoverable)
        XCTAssertFalse(SelectShortcutReplyIntent.isDiscoverable)
    }

    func testConfirmationSnippetIntentPreservesCompletePresentationPayload() {
        let longReply = String(repeating: "Complete reply text. ", count: 30)
        let intent = ShortcutRepliesConfirmationSnippetIntent(
            selectionSessionID: "session-123",
            chatID: "chat-123",
            chatTitle: "Natalie",
            importedMessageCount: 9,
            reviewRequired: true,
            duplicate: false,
            replies: [longReply, "Second reply"]
        )

        XCTAssertEqual(intent.selectionSessionID, "session-123")
        XCTAssertEqual(intent.chatID, "chat-123")
        XCTAssertEqual(intent.chatTitle, "Natalie")
        XCTAssertEqual(intent.importedMessageCount, 9)
        XCTAssertTrue(intent.reviewRequired)
        XCTAssertFalse(intent.duplicate)
        XCTAssertEqual(intent.replies, [longReply, "Second reply"])
    }

    @MainActor
    func testReplySelectionIsScopedAndDefaultsToFirstReply() {
        ShortcutReplySelectionStore.shared.reset()
        defer { ShortcutReplySelectionStore.shared.reset() }

        ShortcutReplySelectionStore.shared.begin(sessionID: "session-1")
        ShortcutReplySelectionStore.shared.begin(sessionID: "session-2")

        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-1",
                replyCount: 2
            ),
            0
        )

        ShortcutReplySelectionStore.shared.select(
            replyIndex: 1,
            sessionID: "session-1"
        )

        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-1",
                replyCount: 2
            ),
            1
        )
        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-2",
                replyCount: 2
            ),
            0
        )
    }

    @MainActor
    func testConfirmationSnippetReturnsTheCompleteSelectedReply() async throws {
        ShortcutReplySelectionStore.shared.reset()
        defer { ShortcutReplySelectionStore.shared.reset() }

        let completeReply = String(repeating: "Never truncate selected text. ", count: 30)
        let intent = ShortcutRepliesConfirmationSnippetIntent(
            selectionSessionID: "session-123",
            chatID: "chat-123",
            chatTitle: "Natalie",
            importedMessageCount: 9,
            reviewRequired: false,
            duplicate: false,
            replies: ["First reply", completeReply]
        )
        ShortcutReplySelectionStore.shared.begin(sessionID: "session-123")
        ShortcutReplySelectionStore.shared.select(
            replyIndex: 1,
            sessionID: "session-123"
        )

        let result = try await intent.perform()

        XCTAssertEqual(result.value, completeReply)
    }

    func testReplyChoiceOutputPreservesCompleteReplies() {
        let firstReply = String(repeating: "Never truncate copied text. ", count: 30)
        let response = response(
            replies: [firstReply, "Second complete reply"]
        )

        XCTAssertEqual(
            ShortcutReplyChoiceBuilder.values(from: response),
            [firstReply, "Second complete reply"]
        )
    }

    func testReplyChoiceOutputFiltersEmptyValuesAndCapsTheListAtTwo() {
        let response = response(replies: ["", "First", " \n", "Second", "Third"])

        XCTAssertEqual(
            ShortcutReplyChoiceBuilder.values(from: response),
            ["First", "Second"]
        )
    }

    func testReplyChoiceOutputIsEmptyWhenGenerationIsUnavailable() {
        XCTAssertTrue(
            ShortcutReplyChoiceBuilder.values(from: response(replies: nil)).isEmpty
        )
    }

    func testSnippetPresentationUsesPluralAwareReplyHeadings() {
        XCTAssertEqual(
            snippet(replies: ["Only reply"]).headerText,
            "1 reply ready"
        )
        XCTAssertEqual(
            snippet(replies: ["First", "Second"]).headerText,
            "2 replies ready"
        )
    }

    func testSnippetPresentationFormatsImportStates() {
        XCTAssertEqual(
            snippet(importedMessageCount: 1, replies: ["Reply"]).statusText,
            "1 message imported to natalie"
        )
        XCTAssertEqual(
            snippet(importedMessageCount: 9, replies: ["Reply"]).statusText,
            "9 messages imported to natalie"
        )
        XCTAssertEqual(
            snippet(
                importedMessageCount: 9,
                reviewRequired: true,
                replies: ["Reply"]
            ).statusText,
            "9 messages imported to natalie · Review required"
        )
        XCTAssertEqual(
            snippet(duplicate: true, replies: ["Reply"]).statusText,
            "No new messages added to natalie"
        )
    }

    func testSnippetPresentationFiltersEmptyRepliesAndCapsVisibleCardsAtTwo() {
        let view = snippet(replies: ["", "First", "  ", "Second", "Third"])

        XCTAssertEqual(view.visibleReplies, ["First", "Second"])
        XCTAssertFalse(view.showsEmptyState)
    }

    func testSnippetPresentationShowsUnavailableStateWithoutEmptyCards() {
        let view = snippet(replies: ["", "  \n"])

        XCTAssertTrue(view.visibleReplies.isEmpty)
        XCTAssertTrue(view.showsEmptyState)
        XCTAssertEqual(view.headerText, "Replies unavailable")
    }

    @MainActor
    func testLongSnippetRendersWithinRecommendedHeightInBothAppearances() throws {
        let replies = [
            "Мне очень нравится набережная. Там открывается прекрасный вид на Волгу и Оку.",
            "Люблю гулять по Кремлю. Это красивое и историческое место в центре города."
        ]

        for colorScheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(
                content: snippet(
                    replies: replies,
                    selectionSessionID: "session-123",
                    selectedReplyIndex: 0
                )
                .frame(width: 358)
                .environment(\.colorScheme, colorScheme)
            )
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertLessThanOrEqual(image.size.height, 340)
        }
    }

    @MainActor
    func testAccessibilitySnippetUsesCompactLayoutWithinRecommendedHeight() throws {
        let longReply = String(
            repeating: "A long suggested reply remains complete when copied. ",
            count: 10
        )
        let renderer = ImageRenderer(
            content: snippet(
                replies: [longReply, longReply],
                selectionSessionID: "session-123",
                selectedReplyIndex: 0
            )
            .frame(width: 358)
            .environment(\.dynamicTypeSize, .accessibility2)
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertLessThanOrEqual(
            image.size.height,
            340,
            "Accessibility snippet rendered at \(image.size.height) points"
        )
    }

    @MainActor
    func testLargestStandardDynamicTypeKeepsSnippetWithinRecommendedHeight() throws {
        let replies = [
            "Какое у тебя любимое место в Нижнем Новгороде?",
            "А куда в Нижнем Новгороде ты бы посоветовал сходить?"
        ]
        let renderer = ImageRenderer(
            content: snippet(
                replies: replies,
                selectionSessionID: "session-123",
                selectedReplyIndex: 1
            )
            .frame(width: 358)
            .environment(\.dynamicTypeSize, .xxxLarge)
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertLessThanOrEqual(
            image.size.height,
            340,
            "Large-type snippet rendered at \(image.size.height) points"
        )
    }

    private func snippet(
        importedMessageCount: Int = 9,
        reviewRequired: Bool = false,
        duplicate: Bool = false,
        replies: [String],
        selectionSessionID: String? = nil,
        selectedReplyIndex: Int? = nil
    ) -> ShortcutRepliesSnippet {
        ShortcutRepliesSnippet(
            chatID: "chat-123",
            chatTitle: "natalie",
            importedMessageCount: importedMessageCount,
            reviewRequired: reviewRequired,
            duplicate: duplicate,
            replies: replies,
            selectionSessionID: selectionSessionID,
            selectedReplyIndex: selectedReplyIndex
        )
    }

    private func response(replies: [String]?) -> ShortcutResponsePresentation {
        ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .success,
                message: "Imported",
                diagnosticID: "trace-123",
                chatID: "chat-123",
                chatTitle: "natalie",
                appLanguage: "en",
                importID: nil,
                matchedExisting: false,
                reviewRequired: false,
                duplicate: false,
                insertedMessageCount: 9,
                errorCode: nil,
                suggestedReplies: replies,
                replyStatus: replies == nil ? .failed : .generated,
                replyErrorCode: replies == nil ? "reply_generation_failed" : nil
            ),
            dialog: "Imported"
        )
    }
}
