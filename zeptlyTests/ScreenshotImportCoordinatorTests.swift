import SwiftData
import XCTest
@testable import zeptly

final class ScreenshotImportCoordinatorTests: XCTestCase {
    @MainActor
    func testCoordinatorRunsOCRAnalysisMatchingAndPersistence() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let credentials = StubProviderConfiguration()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Sarah Jenkins",
            participants: ["Sarah Jenkins"],
            messages: [
                AnalyzedChatMessage(
                    sender: .user,
                    senderName: nil,
                    text: "A newly imported reply",
                    timestampLabel: "11:00 AM"
                )
            ],
            matchedChatID: "sarah-jenkins",
            matchConfidence: 0.97
        )
        let coordinator = ScreenshotImportCoordinator(
            ocrService: StubOCRService(),
            providerStore: credentials,
            repository: repository,
            clientResolver: { _ in StubAnalysisClient(analysis: analysis) }
        )

        let outcome = try await coordinator.process(imageData: Data("transient image bytes".utf8))

        XCTAssertEqual(outcome.chatID, "sarah-jenkins")
        XCTAssertEqual(outcome.insertedMessageCount, 1)
        XCTAssertFalse(outcome.reviewRequired)
        XCTAssertTrue(
            try repository.messages(chatID: "sarah-jenkins")
                .contains { $0.text == "A newly imported reply" }
        )
    }
}

nonisolated private struct StubOCRService: ScreenshotOCRService {
    func recognizeText(in imageData: Data) async throws -> OCRDocument {
        OCRDocument(
            lines: [
                OCRLine(
                    text: "A newly imported reply",
                    confidence: 0.99,
                    boundingBox: OCRBoundingBox(x: 0.5, y: 0.5, width: 0.4, height: 0.1)
                )
            ]
        )
    }
}

@MainActor
private final class StubProviderConfiguration: ProviderConfigurationProviding {
    let activeProvider: ProviderConnection? = ProviderConnection(
        platform: .openAI,
        model: .gpt54Mini,
        lastValidatedAt: Date(),
        validationState: .connected
    )

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        "test-key"
    }
}

@MainActor
private struct StubAnalysisClient: AIProviderClient {
    let analysis: ChatImportAnalysis

    func validate(apiKey: String, model: ProviderModel) async throws {}

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        apiKey: String,
        model: ProviderModel
    ) async throws -> ChatImportAnalysis {
        analysis
    }
}
