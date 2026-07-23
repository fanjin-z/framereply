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
    func testRejectsOverlongDraftingInputBeforeImport() async {
        let importer = StubInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 1, reviewRequired: false)
        )
        let replies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let result = await viewModel.importScreenshots(
            [Data([1])],
            draftingInput: String(repeating: "a", count: 501)
        )

        XCTAssertNil(result)
        XCTAssertTrue(importer.receivedImageDataList.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Keep context under 500 characters.")
        XCTAssertTrue(replies.requests.isEmpty)
    }

    @MainActor
    func testCancellationBeforeImportCompletionProducesNoResult() async {
        let importer = CancellableInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 1, reviewRequired: false)
        )
        let replies = StubInAppReplies(
            outcome: SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
        )
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let task = Task {
            await viewModel.importScreenshots([Data([1])])
        }
        while !importer.didStart {
            await Task.yield()
        }
        task.cancel()

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(replies.requests.isEmpty)
    }

    @MainActor
    func testCancellationDuringReplyGenerationPreservesImportResult() async {
        let importer = StubInAppImporter(
            outcome: makeOutcome(insertedMessageCount: 1, reviewRequired: false)
        )
        let replies = CancellableInAppReplies()
        let viewModel = InAppScreenshotImportViewModel(
            importer: importer,
            repliesGenerator: replies
        )

        let task = Task {
            await viewModel.importScreenshots([Data([1])])
        }
        while !replies.didStart {
            await Task.yield()
        }
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result?.chatID, "chat-1")
        XCTAssertNil(result?.replies)
        XCTAssertEqual(result?.replyErrorMessage, "Reply generation canceled.")
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

@MainActor
private final class CancellableInAppImporter: ScreenshotImportProcessing {
    let outcome: ScreenshotImportOutcome
    private(set) var didStart = false

    init(outcome: ScreenshotImportOutcome) {
        self.outcome = outcome
    }

    func process(
        imageDataList: [Data],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome {
        didStart = true
        try await Task.sleep(for: .seconds(60))
        return outcome
    }
}

@MainActor
private final class CancellableInAppReplies: InAppSuggestedRepliesGenerating {
    private(set) var didStart = false

    func generate(
        chatID: String,
        draftingInput: String?,
        force: Bool,
        localization: LocalizationContext,
        traceID: ImportTraceID
    ) async throws -> SuggestedRepliesOutcome {
        didStart = true
        try await Task.sleep(for: .seconds(60))
        return SuggestedRepliesOutcome(replies: ["First", "Second"], source: .generated)
    }
}
