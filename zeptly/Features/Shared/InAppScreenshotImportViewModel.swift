//
//  InAppScreenshotImportViewModel.swift
//  zeptly
//

import Combine
import Foundation

struct InAppScreenshotImportResult: Equatable {
    let outcome: ScreenshotImportOutcome
    let replies: SuggestedRepliesOutcome?
    let replyErrorMessage: String?

    var chatID: String { outcome.chatID }

    var message: String {
        let count = outcome.insertedMessageCount
        let noun = count == 1 ? "message" : "messages"
        if outcome.duplicate {
            return "No new messages found in \(outcome.chatName)."
        }
        if outcome.reviewRequired {
            return "Imported \(count) \(noun). Review may be needed."
        }
        return "Added \(count) \(noun) to \(outcome.chatName)."
    }
}

enum InAppChatImportKind: Equatable {
    case screenshots
    case copiedMessages
}

@MainActor
protocol ScreenshotImportProcessing {
    func process(
        imageDataList: [Data],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome

    func process(
        transcriptItems: [String],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome
}

extension ScreenshotImportProcessing {
    func process(
        transcriptItems: [String],
        traceID: ImportTraceID
    ) async throws -> ScreenshotImportOutcome {
        throw ScreenshotImportError.noTranscript
    }
}

extension ScreenshotImportCoordinator: ScreenshotImportProcessing {}

@MainActor
protocol InAppSuggestedRepliesGenerating {
    func generate(
        chatID: String,
        draftingInput: String?,
        force: Bool,
        traceID: ImportTraceID
    ) async throws -> SuggestedRepliesOutcome
}

extension SuggestedRepliesCoordinator: InAppSuggestedRepliesGenerating {}

@MainActor
final class InAppScreenshotImportViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var importKind: InAppChatImportKind = .screenshots
    @Published private(set) var result: InAppScreenshotImportResult?
    @Published private(set) var errorMessage: String?

    private let importer: any ScreenshotImportProcessing
    private let repliesGenerator: any InAppSuggestedRepliesGenerating
    private var loadID = 0

    convenience init() {
        self.init(providerStore: ProviderStore())
    }

    convenience init(providerStore: any ProviderConfigurationProviding) {
        self.init(
            importer: ScreenshotImportCoordinator(
                aiService: AIService(
                    providerConfiguration: providerStore,
                    registry: .live(eventReporter: OSLogImportEventReporter())
                ),
                repository: ChatRepository()
            ),
            repliesGenerator: SuggestedRepliesCoordinator(providerStore: providerStore)
        )
    }

    init(
        importer: any ScreenshotImportProcessing,
        repliesGenerator: any InAppSuggestedRepliesGenerating
    ) {
        self.importer = importer
        self.repliesGenerator = repliesGenerator
    }

    @discardableResult
    func importScreenshots(
        _ imageDataList: [Data],
        draftingInput: String? = nil
    ) async -> InAppScreenshotImportResult? {
        let images = imageDataList.filter { !$0.isEmpty }
        guard !images.isEmpty else {
            result = nil
            errorMessage = "Select at least one screenshot."
            return nil
        }

        return await performImport(kind: .screenshots, draftingInput: draftingInput) {
            try await self.importer.process(imageDataList: images, traceID: $0)
        }
    }

    @discardableResult
    func importCopiedMessages(
        _ transcriptItems: [String],
        draftingInput: String? = nil
    ) async -> InAppScreenshotImportResult? {
        let items = transcriptItems.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !items.isEmpty else {
            result = nil
            errorMessage = ScreenshotImportError.noTranscript.localizedDescription
            return nil
        }

        return await performImport(kind: .copiedMessages, draftingInput: draftingInput) {
            try await self.importer.process(transcriptItems: items, traceID: $0)
        }
    }

    private func performImport(
        kind: InAppChatImportKind,
        draftingInput: String?,
        importOperation: @escaping (ImportTraceID) async throws -> ScreenshotImportOutcome
    ) async -> InAppScreenshotImportResult? {

        loadID += 1
        let currentLoadID = loadID
        let traceID = ImportTraceID()
        importKind = kind
        result = nil
        errorMessage = nil
        isLoading = true
        defer {
            if loadID == currentLoadID {
                isLoading = false
            }
        }

        do {
            let outcome = try await importOperation(traceID)
            try Task.checkCancellation()
            guard loadID == currentLoadID else { return nil }

            let replies: SuggestedRepliesOutcome?
            let replyErrorMessage: String?
            do {
                replies = try await repliesGenerator.generate(
                    chatID: outcome.chatID,
                    draftingInput: draftingInput,
                    force: true,
                    traceID: traceID
                )
                replyErrorMessage = nil
            } catch is CancellationError {
                return nil
            } catch {
                replies = nil
                replyErrorMessage = error.localizedDescription
            }

            try Task.checkCancellation()
            guard loadID == currentLoadID else { return nil }

            let result = InAppScreenshotImportResult(
                outcome: outcome,
                replies: replies,
                replyErrorMessage: replyErrorMessage
            )
            self.result = result
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard loadID == currentLoadID else { return nil }
            result = nil
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
