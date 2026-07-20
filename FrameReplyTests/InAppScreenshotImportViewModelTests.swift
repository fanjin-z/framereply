import Foundation
import XCTest

@testable import FrameReply

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
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testSeparatesReplyFailureFromImportFailure() async throws {
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
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)

        let failedImporter = StubInAppImporter(error: StubError(message: "Provider failed"))
        let unusedReplies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let failedViewModel = InAppScreenshotImportViewModel(
            importer: failedImporter,
            repliesGenerator: unusedReplies
        )

        let failedResult = await failedViewModel.importScreenshots([Data([1])])

        XCTAssertNil(failedResult)
        XCTAssertNil(failedViewModel.result)
        XCTAssertEqual(failedViewModel.errorMessage, "Provider failed")
        XCTAssertTrue(unusedReplies.requests.isEmpty)
        XCTAssertFalse(failedViewModel.isLoading)
    }

    @MainActor
    private func makeOutcome(
        insertedMessageCount: Int,
        reviewRequired: Bool
    ) -> ScreenshotImportOutcome {
        ScreenshotImportOutcome(
            chatID: "chat-1",
            chatTitle: "Sarah",
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
        localization: LocalizationContext,
        traceID: ImportTraceID
    ) async throws -> SuggestedRepliesOutcome {
        requests.append(Request(chatID: chatID, draftingInput: draftingInput, force: force))
        if let error {
            throw error
        }
        return outcome!
    }
}
