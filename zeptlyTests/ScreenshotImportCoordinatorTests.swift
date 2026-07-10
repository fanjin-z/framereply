import SwiftData
import XCTest

@testable import zeptly

final class ScreenshotImportCoordinatorTests: XCTestCase {
    @MainActor
    func testCoordinatorSendsTransientImageToAnalysisAndPersistsTranscriptOnly() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        container.mainContext.insert(
            ChatRecord(
                id: "sarah-jenkins",
                name: "Sarah Jenkins",
                lastActivityLabel: "Recent",
                preview: "Existing conversation",
                chipTitle: "General",
                chipSymbol: "number",
                avatarSymbol: nil,
                initials: "SJ",
                appearanceStyle: 0,
                isUnread: false
            )
        )
        let analysis = ChatImportAnalysis(
            conversationTitle: "Sarah Jenkins",
            messages: [
                AnalyzedChatMessage(
                    sender: .user,
                    senderName: nil,
                    text: "A newly imported reply",
                    timestampLabel: "11:00 AM",
                    outerAlignment: .right,
                    senderConfidence: 0.99,
                    senderEvidence: .messageStatusIndicator
                ),
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Sarah Jenkins",
                    text: "你好，很高兴认识你",
                    timestampLabel: "11:01 AM",
                    outerAlignment: .left,
                    senderConfidence: 0.95,
                    senderEvidence: .alignmentConvention
                ),
                AnalyzedChatMessage(
                    sender: .other,
                    senderName: "Inna",
                    text: String(repeating: "A longer group reply. ", count: 20),
                    timestampLabel: nil,
                    outerAlignment: .left,
                    senderConfidence: 0.95,
                    senderEvidence: .alignmentConvention
                )
            ],
            matchedChatID: "sarah-jenkins",
            matchConfidence: 0.97,
            conversationKind: .group,
            ownershipConvention: MessageOwnershipConvention(
                mode: .opposedAlignment,
                screenshotOwnerAlignment: .right,
                screenshotOwnerAuthorLabel: nil
            )
        )
        let reporter = CoordinatorEventReporter()
        let aiService = StubAnalysisService(analysis: analysis)
        let coordinator = ScreenshotImportCoordinator(
            aiService: aiService,
            repository: repository,
            eventReporter: reporter
        )

        let traceID = ImportTraceID(
            value: UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        let outcome = try await coordinator.process(
            imageData: imageData,
            traceID: traceID
        )

        XCTAssertEqual(outcome.chatID, "sarah-jenkins")
        XCTAssertEqual(outcome.chatName, "Sarah Jenkins")
        XCTAssertEqual(outcome.diagnosticID, "12345678")
        XCTAssertEqual(outcome.insertedMessageCount, 3)
        XCTAssertFalse(outcome.reviewRequired)
        XCTAssertEqual(aiService.receivedImageData, imageData)
        XCTAssertEqual(aiService.receivedImageDataList, [imageData])
        XCTAssertEqual(aiService.receivedContext?.effectiveModel, .gpt54Mini)
        let messages = try repository.messages(chatID: "sarah-jenkins")
        XCTAssertTrue(
            messages.contains { $0.text == "A newly imported reply" && $0.senderKind == "user" })
        XCTAssertTrue(messages.contains { $0.text == "你好，很高兴认识你" && $0.senderKind == "contact" })
        XCTAssertTrue(messages.contains { $0.senderKind == "other" && $0.senderName == "Inna" })
        XCTAssertTrue(
            reporter.events.contains { event in
                guard case .importCompleted(let eventTraceID, _, _, _, let inserted) = event else {
                    return false
                }
                return eventTraceID == traceID && inserted == 3
            })
    }

    @MainActor
    func testCoordinatorProcessesMultipleImagesInOneAnalysisRequest() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        let analysis = ChatImportAnalysis(
            conversationTitle: "Sarah Jenkins",
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: "Sarah Jenkins",
                    text: "Can we meet tomorrow?",
                    timestampLabel: "10:42 AM",
                    outerAlignment: .left,
                    senderConfidence: 0.95,
                    senderEvidence: .alignmentConvention
                )
            ],
            matchedChatID: nil,
            matchConfidence: 0,
            ownershipConvention: MessageOwnershipConvention(
                mode: .opposedAlignment,
                screenshotOwnerAlignment: .right,
                screenshotOwnerAuthorLabel: nil
            )
        )
        let aiService = StubAnalysisService(analysis: analysis)
        let coordinator = ScreenshotImportCoordinator(
            aiService: aiService,
            repository: repository
        )
        let images = [
            Data([0x89, 0x50, 0x4E, 0x47, 0x01]),
            Data([0xFF, 0xD8, 0xFF, 0xE0, 0x02])
        ]

        let outcome = try await coordinator.process(imageDataList: images)

        XCTAssertEqual(aiService.receivedImageDataList, images)
        XCTAssertEqual(outcome.insertedMessageCount, 1)
        XCTAssertTrue(outcome.reviewRequired)
        XCTAssertEqual(try repository.messages(chatID: outcome.chatID).map(\.text), [
            "Can we meet tomorrow?"
        ])
    }
}

private final class CoordinatorEventReporter: ImportEventReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImportEvent] = []

    var events: [ImportEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: ImportEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

@MainActor
private final class StubAnalysisService: AIServiceProviding {
    let analysis: ChatImportAnalysis
    private(set) var receivedImageData: Data?
    private(set) var receivedImageDataList: [Data] = []
    private(set) var receivedContext: AIProviderExecutionContext?

    private let context = AIProviderExecutionContext(
        platform: .openAI,
        profile: ProviderModelProfile(
            selectedModel: .gpt54Mini,
            screenshotAnalysisModel: .gpt54Mini,
            suggestedReplyModel: .gpt54Mini
        ),
        capability: .screenshotAnalysis,
        effectiveModel: .gpt54Mini
    )

    init(analysis: ChatImportAnalysis) {
        self.analysis = analysis
    }

    func activeContext(
        requiring capability: AIProviderCapability
    ) throws -> AIProviderExecutionContext {
        guard capability == .screenshotAnalysis else {
            throw AIServiceError.unsupportedCapability
        }
        return context
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis {
        receivedImageData = request.imageData
        receivedImageDataList = request.imageDataList
        receivedContext = context
        return analysis
    }

    func generateSuggestedReplies(
        _ request: SuggestedReplyGenerationRequest,
        using context: AIProviderExecutionContext
    ) async throws -> SuggestedReplyGenerationResult {
        throw AIServiceError.unsupportedCapability
    }
}
