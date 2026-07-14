import Foundation
import XCTest

@testable import zeptly

final class InAppScreenshotImportViewModelTests: XCTestCase {
    @MainActor
    func testImportsScreenshotsAndGeneratesReplies() async throws {
        let importer = StubInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 2, reviewRequired: false)
        )
        let replies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let result = await viewModel.importScreenshots(
            [Data([1]), Data(), Data([2])],
            draftingInput: "Use this context"
        )

        XCTAssertEqual(importer.receivedImageDataList, [Data([1]), Data([2])])
        XCTAssertEqual(replies.requests.map(\.chatID), ["chat-1"])
        XCTAssertEqual(replies.requests.first?.draftingInput, "Use this context")
        XCTAssertEqual(result?.replies?.replies, ["First", "Second"])
        XCTAssertEqual(viewModel.result?.message, "Added 2 messages to Sarah.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testKeepsSuccessfulImportWhenReplyGenerationFails() async throws {
        let importer = StubInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 1, reviewRequired: true)
        )
        let replies = StubInAppReplies(error: StubError(message: "No provider"))
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let result = await viewModel.importScreenshots([Data([1])])

        XCTAssertEqual(result?.chatID, "chat-1")
        XCTAssertNil(result?.replies)
        XCTAssertEqual(result?.replyErrorMessage, "No provider")
        XCTAssertEqual(viewModel.result?.message, "Imported 1 message. Review may be needed.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testImportFailureSetsErrorWithoutGeneratingReplies() async throws {
        let importer = StubInAppImporter(error: StubError(message: "Provider failed"))
        let replies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let result = await viewModel.importScreenshots([Data([1])])

        XCTAssertNil(result)
        XCTAssertNil(viewModel.result)
        XCTAssertEqual(viewModel.errorMessage, "Provider failed")
        XCTAssertTrue(replies.requests.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testImportsCopiedMessagesAndStillGeneratesRepliesWhenReviewIsRequired() async throws {
        let importer = StubInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 2, reviewRequired: true)
        )
        let replies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let result = await viewModel.importCopiedMessages(
            ["Alice - 9:42 PM - Hello", " ", "Me - 9:43 PM - Hi"]
        )

        XCTAssertEqual(
            importer.receivedTranscriptItems,
            ["Alice - 9:42 PM - Hello", "Me - 9:43 PM - Hi"]
        )
        XCTAssertEqual(viewModel.importKind, .copiedMessages)
        XCTAssertTrue(result?.outcome.reviewRequired == true)
        XCTAssertEqual(result?.replies?.replies, ["First", "Second"])
        XCTAssertEqual(replies.requests.map(\.chatID), ["chat-1"])
    }

    @MainActor
    private func makeOutcome(
        insertedMessageCount: Int,
        reviewRequired: Bool
    ) -> ScreenshotImportOutcome {
        ScreenshotImportOutcome(
            chatID: "chat-1",
            chatName: "Sarah",
            importID: UUID(),
            diagnosticID: "ABC12345",
            matchedExisting: true,
            reviewRequired: reviewRequired,
            duplicate: false,
            insertedMessageCount: insertedMessageCount
        )
    }
}

private struct StubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class StubInAppImporter: ScreenshotImportProcessing {
    private let outcome: ScreenshotImportOutcome?
    private let error: Error?
    private(set) var receivedImageDataList: [Data] = []
    private(set) var receivedTranscriptItems: [String] = []

    init(outcome: ScreenshotImportOutcome? = nil, error: Error? = nil) {
        self.outcome = outcome
        self.error = error
    }

    func process(
        imageDataList: [Data],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome {
        receivedImageDataList = imageDataList
        if let error {
            throw error
        }
        return outcome!
    }

    func process(
        transcriptItems: [String],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome {
        receivedTranscriptItems = transcriptItems
        if let error {
            throw error
        }
        return outcome!
    }
}

@MainActor
private final class StubInAppReplies: InAppSuggestedRepliesGenerating {
    struct Request: Equatable {
        let chatID: String
        let draftingInput: String?
        let force: Bool
    }

    private let outcome: SuggestedRepliesOutcome?
    private let error: Error?
    private(set) var requests: [Request] = []

    init(outcome: SuggestedRepliesOutcome? = nil, error: Error? = nil) {
        self.outcome = outcome
        self.error = error
    }

    func generate(
        chatID: String,
        draftingInput: String?,
        force: Bool,
        traceID: ImportTraceID
    ) async throws -> SuggestedRepliesOutcome {
        requests.append(Request(chatID: chatID, draftingInput: draftingInput, force: force))
        if let error {
            throw error
        }
        return outcome!
    }
}
