import SwiftData
import UIKit
import XCTest

@testable import zeptly

final class ScreenshotImportCoordinatorTests: XCTestCase {
    @MainActor
    func testCoordinatorSendsTransientImagesToAnalysisAndPersistsTranscriptOnly() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        container.mainContext.insert(
            ChatRecord(
                id: "sarah-jenkins",
                name: "Sarah Jenkins",
                preview: "Existing conversation"
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
                    sender: .otherParticipant,
                    senderName: "Sarah Jenkins",
                    text: "你好，很高兴认识你",
                    timestampLabel: "11:01 AM",
                    outerAlignment: .left,
                    senderConfidence: 0.95,
                    senderEvidence: .alignmentConvention
                ),
                AnalyzedChatMessage(
                    sender: .groupParticipant,
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
        let imageDataList = [makeTestImageData(color: .blue), makeTestImageData(color: .green)]
        let outcome = try await coordinator.process(
            imageDataList: imageDataList,
            traceID: traceID
        )

        XCTAssertEqual(outcome.chatID, "sarah-jenkins")
        XCTAssertEqual(outcome.chatName, "Sarah Jenkins")
        XCTAssertEqual(outcome.diagnosticID, "12345678")
        XCTAssertEqual(outcome.insertedMessageCount, 3)
        XCTAssertFalse(outcome.reviewRequired)
        XCTAssertEqual(aiService.receivedImageDataList.count, 2)
        XCTAssertTrue(aiService.receivedImageDataList.allSatisfy { $0.starts(with: [0xFF, 0xD8]) })
        XCTAssertTrue(
            aiService.receivedImageDataList.allSatisfy {
                $0.count <= ScreenshotImageNormalizer.maximumBytesPerImage
            })
        XCTAssertEqual(aiService.receivedContext?.effectiveModel, .gpt56Luna)
        let messages = try repository.messages(chatID: "sarah-jenkins")
        XCTAssertTrue(
            messages.contains { $0.text == "A newly imported reply" && $0.senderKind == "user" })
        XCTAssertTrue(
            messages.contains {
                $0.text == "你好，很高兴认识你" && $0.senderKind == "other_participant"
            })
        XCTAssertTrue(
            messages.contains {
                $0.senderKind == "group_participant" && $0.senderName == "Inna"
            })
        XCTAssertTrue(
            reporter.events.contains { event in
                guard case .importCompleted(let eventTraceID, _, _, _, let inserted) = event else {
                    return false
                }
                return eventTraceID == traceID && inserted == 3
            })
    }

    @MainActor
    func testCopiedTextUsesTranscriptAnalysisAndAddsOnlyGenuinelyNewMessages() async throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)
        try repository.seedIfNeeded()
        container.mainContext.insert(
            ChatRecord(
                id: "cross-source-chat",
                name: "Alice",
                preview: "Existing conversation"
            )
        )

        func analysis(messages: [AnalyzedChatMessage]) -> ChatImportAnalysis {
            ChatImportAnalysis(
                conversationTitle: "Alice",
                messages: messages,
                matchedChatID: "cross-source-chat",
                matchConfidence: 0.99,
                titleSource: .header,
                ownershipConvention: MessageOwnershipConvention(
                    mode: .opposedAlignment,
                    screenshotOwnerAlignment: .right,
                    screenshotOwnerAuthorLabel: nil
                )
            )
        }
        let firstMessage = AnalyzedChatMessage(
            sender: .otherParticipant,
            senderName: "Alice",
            text: "Are you free tomorrow?",
            timestampLabel: "9:42 PM",
            outerAlignment: .left,
            senderConfidence: 0.95,
            senderEvidence: .alignmentConvention
        )
        let secondMessage = AnalyzedChatMessage(
            sender: .user,
            senderName: nil,
            text: "Yes, after six.",
            timestampLabel: "9:43 PM",
            outerAlignment: .right,
            senderConfidence: 0.95,
            senderEvidence: .alignmentConvention
        )
        let aiService = StubAnalysisService(analysis: analysis(messages: [firstMessage]))
        let coordinator = ScreenshotImportCoordinator(
            aiService: aiService,
            repository: repository
        )

        let screenshotOutcome = try await coordinator.process(imageData: makeTestImageData())
        aiService.analysis = analysis(messages: [firstMessage, secondMessage])
        let textOutcome = try await coordinator.process(
            transcriptItems: [
                "[07/13/26, 9:42 PM] Alice: Are you free tomorrow?",
                "[07/13/26, 9:43 PM] Me: Yes, after six."
            ]
        )

        XCTAssertEqual(screenshotOutcome.insertedMessageCount, 1)
        XCTAssertEqual(textOutcome.insertedMessageCount, 1)
        XCTAssertEqual(
            aiService.receivedTranscriptItems,
            [
                "[07/13/26, 9:42 PM] Alice: Are you free tomorrow?",
                "[07/13/26, 9:43 PM] Me: Yes, after six."
            ]
        )
        XCTAssertEqual(aiService.receivedContext?.capability, .transcriptAnalysis)
        XCTAssertEqual(aiService.receivedContext?.effectiveModel, .gpt56Terra)
        XCTAssertEqual(
            try repository.messages(chatID: "cross-source-chat").map(\.text),
            ["Are you free tomorrow?", "Yes, after six."]
        )
        XCTAssertNotNil(try repository.importRecord(id: textOutcome.importID))
    }

    @MainActor
    func testCoordinatorRejectsEmptyAndOversizedCopiedMessagesBeforeProviderResolution()
        async throws
    {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let coordinator = ScreenshotImportCoordinator(
            aiService: StubAnalysisService(
                analysis: ChatImportAnalysis(
                    conversationTitle: nil,
                    messages: [],
                    matchedChatID: nil,
                    matchConfidence: 0,
                    titleSource: .unavailable,
                    ownershipConvention: .unobservable
                )
            ),
            repository: ChatRepository(container: container)
        )

        do {
            _ = try await coordinator.process(transcriptItems: [" \n "])
            XCTFail("Expected noTranscript")
        } catch let error as ScreenshotImportError {
            XCTAssertEqual(error.code, "no_transcript")
        }

        do {
            _ = try await coordinator.process(
                transcriptItems: [String(repeating: "a", count: 8_001)]
            )
            XCTFail("Expected transcriptTooLarge")
        } catch let error as ScreenshotImportError {
            XCTAssertEqual(error.code, "transcript_too_large")
        }

        do {
            _ = try await coordinator.process(
                transcriptItems: Array(repeating: "message", count: 41)
            )
            XCTFail("Expected transcriptTooLarge")
        } catch let error as ScreenshotImportError {
            XCTAssertEqual(error.code, "transcript_too_large")
        }

        let combined = (1...26).map { index in
            "[07/13/26, 9:\(String(format: "%02d", index)) PM] Alice: Message \(index)"
        }.joined(separator: "\n")
        do {
            _ = try await coordinator.process(transcriptItems: [combined])
            XCTFail("Expected transcriptTooLarge")
        } catch let error as ScreenshotImportError {
            XCTAssertEqual(error.code, "transcript_too_large")
        }
    }
}

@MainActor
private func makeTestImageData(color: UIColor = .purple) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 96))
    return renderer.jpegData(withCompressionQuality: 0.95) { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 96))
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
    var analysis: ChatImportAnalysis
    private(set) var receivedImageDataList: [Data] = []
    private(set) var receivedTranscriptItems: [String] = []
    private(set) var receivedContext: AIProviderExecutionContext?

    private let context = AIProviderExecutionContext(
        platform: .openAI,
        capability: .screenshotAnalysis,
        effectiveModel: .gpt56Luna
    )

    init(analysis: ChatImportAnalysis) {
        self.analysis = analysis
    }

    func activeContext(
        requiring capability: AIProviderCapability
    ) throws -> AIProviderExecutionContext {
        guard capability == .screenshotAnalysis || capability == .transcriptAnalysis
        else {
            throw AIServiceError.unsupportedCapability
        }
        let model: ProviderModel = capability == .transcriptAnalysis ? .gpt56Terra : .gpt56Luna
        return AIProviderExecutionContext(
            platform: context.platform,
            capability: capability,
            effectiveModel: model
        )
    }

    func analyzeChatScreenshot(
        _ request: ChatScreenshotAnalysisRequest,
        using context: AIProviderExecutionContext
    ) async throws -> ChatImportAnalysis {
        receivedImageDataList = request.imageDataList
        receivedTranscriptItems = request.sharedTranscript?.items ?? []
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
