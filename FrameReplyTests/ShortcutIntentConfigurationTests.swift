import SwiftUI
import XCTest

@testable import FrameReply

final class ShortcutIntentConfigurationTests: XCTestCase {
    func testIntentDiscoveryAndLaunchContract() {
        XCTAssertTrue(SuggestRepliesFromChatImagesIntent().askForContext)
        XCTAssertTrue(SuggestRepliesFromChatTextIntent().askForContext)
        XCTAssertTrue(SuggestRepliesFromChatImagesIntent.isDiscoverable)
        XCTAssertTrue(SuggestRepliesFromChatTextIntent.isDiscoverable)
        XCTAssertFalse(SuggestRepliesFromChatImagesIntent.openAppWhenRun)
        XCTAssertFalse(SuggestRepliesFromChatTextIntent.openAppWhenRun)
        XCTAssertFalse(ShortcutRepliesConfirmationSnippetIntent.isDiscoverable)
        XCTAssertFalse(ShortcutImportReviewSnippetIntent.isDiscoverable)
        XCTAssertFalse(SelectShortcutReplyIntent.isDiscoverable)
    }

    func testReplyConfirmationStateRoutesChoicesWaitReviewAndFailures() throws {
        XCTAssertEqual(
            ShortcutReplyConfirmationState(
                response: response(replies: ["First", "Second"], reviewRequired: true)
            ),
            .replyChoices(["First", "Second"])
        )
        XCTAssertEqual(
            ShortcutReplyConfirmationState(
                response: response(replies: [], dialog: "Wait for their response.")
            ),
            .waitRecommendation("Wait for their response.")
        )

        let reviewResponse = response(
            replies: nil,
            reviewRequired: true,
            duplicate: true,
            message: "No new messages found in natalie.",
            replyErrorCode: SuggestedRepliesError.senderReviewRequired.code
        )
        let presentation = try XCTUnwrap(
            ShortcutImportReviewPresentation(response: reviewResponse)
        )
        XCTAssertEqual(
            ShortcutReplyConfirmationState(response: reviewResponse),
            .senderReviewRequired(presentation)
        )
        XCTAssertEqual(presentation.chatID, "chat-123")
        XCTAssertEqual(presentation.chatTitle, "natalie")
        XCTAssertEqual(presentation.statusMessage, "No new messages found in natalie.")
        XCTAssertEqual(presentation.importedMessageCount, 9)
        XCTAssertTrue(presentation.duplicate)

        XCTAssertEqual(
            ShortcutReplyConfirmationState(
                response: response(
                    replies: nil,
                    chatID: nil,
                    reviewRequired: true,
                    replyErrorCode: SuggestedRepliesError.senderReviewRequired.code
                )
            ),
            .unavailable
        )
        for errorCode in [
            "no_provider", "provider_consent_required", "provider_connection_failed",
            "reply_schema_mismatch"
        ] {
            XCTAssertEqual(
                ShortcutReplyConfirmationState(
                    response: response(
                        replies: nil,
                        reviewRequired: true,
                        replyErrorCode: errorCode
                    )
                ),
                .unavailable,
                errorCode
            )
        }
    }

    @MainActor
    func testOpenShortcutImportPublishesReviewNavigationRequest() async throws {
        let intent = OpenShortcutImportIntent(
            chatID: "review-chat-123",
            reviewRequired: true
        )

        _ = try await intent.perform()

        XCTAssertEqual(ShortcutNavigationCenter.shared.request?.chatID, "review-chat-123")
        XCTAssertEqual(ShortcutNavigationCenter.shared.request?.reviewRequired, true)
    }

    @MainActor
    func testReplySelectionIsScopedAndDefaultsToFirstReply() {
        ShortcutReplySelectionStore.shared.reset()
        defer { ShortcutReplySelectionStore.shared.reset() }

        ShortcutReplySelectionStore.shared.begin(sessionID: "session-1")
        ShortcutReplySelectionStore.shared.begin(sessionID: "session-2")
        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-1", replyCount: 2
            ),
            0
        )

        ShortcutReplySelectionStore.shared.select(replyIndex: 1, sessionID: "session-1")

        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-1", replyCount: 2
            ),
            1
        )
        XCTAssertEqual(
            ShortcutReplySelectionStore.shared.selectedReplyIndex(
                sessionID: "session-2", replyCount: 2
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

    func testReplyChoiceOutputFiltersCapsAndPreservesCompleteReplies() {
        let completeReply = String(repeating: "Never truncate copied text. ", count: 30)
        XCTAssertEqual(
            ShortcutReplyChoiceBuilder.values(
                from: response(replies: [completeReply, "Second complete reply"])
            ),
            [completeReply, "Second complete reply"]
        )
        XCTAssertEqual(
            ShortcutReplyChoiceBuilder.values(
                from: response(replies: ["", "First", " \n", "Second", "Third"])
            ),
            ["First", "Second"]
        )
        XCTAssertTrue(
            ShortcutReplyChoiceBuilder.values(from: response(replies: nil)).isEmpty
        )
    }

    func testSnippetPresentationFormatsReplyAndImportStates() {
        XCTAssertEqual(snippet(replies: ["Only reply"]).headerText, "1 reply ready")
        XCTAssertEqual(snippet(replies: ["First", "Second"]).headerText, "2 replies ready")

        let cases: [(ShortcutRepliesSnippet, String)] = [
            (snippet(importedMessageCount: 1, replies: ["Reply"]), "1 message imported to natalie"),
            (
                snippet(importedMessageCount: 9, replies: ["Reply"]),
                "9 messages imported to natalie"
            ),
            (
                snippet(importedMessageCount: 9, reviewRequired: true, replies: ["Reply"]),
                "9 messages imported to natalie · Review required"
            ),
            (snippet(duplicate: true, replies: ["Reply"]), "No new messages added to natalie")
        ]
        for (view, expected) in cases {
            XCTAssertEqual(view.statusText, expected)
        }
    }

    func testSnippetPresentationFiltersRepliesAndShowsUnavailableState() {
        let filtered = snippet(replies: ["", "First", "  ", "Second", "Third"])
        XCTAssertEqual(filtered.visibleReplies, ["First", "Second"])
        XCTAssertFalse(filtered.showsEmptyState)

        let unavailable = snippet(replies: ["", "  \n"])
        XCTAssertTrue(unavailable.visibleReplies.isEmpty)
        XCTAssertTrue(unavailable.showsEmptyState)
        XCTAssertEqual(unavailable.headerText, "Replies unavailable")
    }

    func testReviewSnippetUsesConciseSenderCheckCopy() {
        let view = reviewSnippet()

        XCTAssertEqual(view.headerText, "Sender check needed")
        XCTAssertEqual(view.chatID, "chat-123")
        XCTAssertTrue(view.duplicate)
    }

    @MainActor
    func testSnippetLayoutsStayWithinRecommendedHeight() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            try assertRecommendedHeight(
                reviewSnippet(),
                colorScheme: colorScheme,
                dynamicTypeSize: .accessibility2
            )
        }

        let localizedReplies = [
            "Мне очень нравится набережная. Там открывается прекрасный вид на Волгу и Оку.",
            "Люблю гулять по Кремлю. Это красивое и историческое место в центре города."
        ]
        for colorScheme in [ColorScheme.light, .dark] {
            try assertRecommendedHeight(
                snippet(
                    replies: localizedReplies,
                    selectionSessionID: "session-123",
                    selectedReplyIndex: 0
                ),
                colorScheme: colorScheme
            )
        }

        let longReply = String(
            repeating: "A long suggested reply remains complete when copied. ",
            count: 10
        )
        try assertRecommendedHeight(
            snippet(
                replies: [longReply, longReply],
                selectionSessionID: "session-123",
                selectedReplyIndex: 0
            ),
            dynamicTypeSize: .accessibility2
        )
        try assertRecommendedHeight(
            snippet(
                replies: [
                    "Какое у тебя любимое место в Нижнем Новгороде?",
                    "А куда в Нижнем Новгороде ты бы посоветовал сходить?"
                ],
                selectionSessionID: "session-123",
                selectedReplyIndex: 1
            ),
            dynamicTypeSize: .xxxLarge
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

    private func reviewSnippet() -> ShortcutImportReviewSnippet {
        ShortcutImportReviewSnippet(
            chatID: "chat-123",
            chatTitle: "natalie",
            statusMessage: "No new messages found in natalie, but review is still required.",
            importedMessageCount: 9,
            duplicate: true
        )
    }

    @MainActor
    private func assertRecommendedHeight<Content: View>(
        _ content: Content,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let renderer = ImageRenderer(
            content:
                content
                .frame(width: 358)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.uiImage, file: file, line: line)
        XCTAssertLessThanOrEqual(image.size.height, 340, file: file, line: line)
    }

    private func response(
        replies: [String]?,
        chatID: String? = "chat-123",
        reviewRequired: Bool = false,
        duplicate: Bool = false,
        message: String = "Imported",
        dialog: String = "Imported",
        replyErrorCode: String? = nil
    ) -> ShortcutResponsePresentation {
        ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .success,
                message: message,
                diagnosticID: "trace-123",
                chatID: chatID,
                chatTitle: "natalie",
                appLanguage: "en",
                importID: nil,
                matchedExisting: false,
                reviewRequired: reviewRequired,
                duplicate: duplicate,
                insertedMessageCount: 9,
                errorCode: nil,
                suggestedReplies: replies,
                replyStatus: replies == nil ? .failed : .generated,
                replyErrorCode: replies == nil
                    ? (replyErrorCode ?? "reply_generation_failed") : nil
            ),
            dialog: dialog
        )
    }
}
