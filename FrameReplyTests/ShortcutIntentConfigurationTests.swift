import AppIntents
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

    func testNetworkFailuresUseTheSystemAppIntentNetworkError() {
        let traceID = ImportTraceID()

        XCTAssertThrowsError(
            try ShortcutErrorSupport.rethrowNetworkFailure(
                .networkFailure("The network connection was lost."),
                traceID: traceID,
                stage: .provider
            )
        ) { error in
            XCTAssertEqual(
                error as? AppIntentError,
                AppIntentError.Unrecoverable.networkFailure
            )
        }

        XCTAssertNoThrow(
            try ShortcutErrorSupport.rethrowNetworkFailure(
                .providerUnavailable,
                traceID: traceID,
                stage: .provider
            )
        )
        XCTAssertEqual(
            ProviderConnectionError.networkFailure("offline").shortcutErrorCode,
            "provider_network_failure"
        )
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
