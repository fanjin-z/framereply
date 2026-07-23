//
//  InAppScreenshotImportViewModel.swift
//  FrameReply
//

import Combine
import Foundation

struct InAppScreenshotImportResult: Equatable {
    let outcome: ScreenshotImportOutcome
    let replies: SuggestedRepliesOutcome?
    let replyErrorMessage: String?
    let localization: LocalizationContext

    var chatID: String { outcome.chatID }

    var message: String {
        let count = outcome.insertedMessageCount
        let chatTitle =
            outcome.chatTitle
            ?? AppStrings.resolve(AppStrings.Chat.importedFallback, locale: localization.locale)
        if outcome.duplicate {
            return AppStrings.resolve(
                AppStrings.Import.noNewMessages(chatTitle: chatTitle),
                locale: localization.locale
            )
        }
        if outcome.reviewRequired {
            return AppStrings.resolve(
                AppStrings.Import.reviewRequired(count: count), locale: localization.locale
            )
        }
        return AppStrings.resolve(
            AppStrings.Import.addedMessages(count: count, chatTitle: chatTitle),
            locale: localization.locale
        )
    }
}

enum InAppChatImportKind: Equatable {
    case screenshots
    case copiedMessages
}

enum InAppChatImportPhase: Equatable {
    case analyzing
    case generatingReplies
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
        localization: LocalizationContext,
        traceID: ImportTraceID
    ) async throws -> SuggestedRepliesOutcome
}

extension SuggestedRepliesCoordinator: InAppSuggestedRepliesGenerating {}

@MainActor
final class InAppScreenshotImportViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var importKind: InAppChatImportKind = .screenshots
    @Published private(set) var phase: InAppChatImportPhase = .analyzing
    @Published private(set) var result: InAppScreenshotImportResult?
    @Published private(set) var errorMessage: String?

    private let importer: any ScreenshotImportProcessing
    private let repliesGenerator: any InAppSuggestedRepliesGenerating
    private let localization: LocalizationContext
    private var loadID = 0

    convenience init() {
        self.init(providerStore: ProviderStore())
    }

    convenience init(
        providerStore: any ProviderConfigurationProviding,
        destinationChatID: String? = nil
    ) {
        self.init(
            importer: ScreenshotImportCoordinator(
                aiService: AIService(
                    providerConfiguration: providerStore,
                    registry: .live(eventReporter: OSLogImportEventReporter())
                ),
                repository: ChatRepository(),
                destinationChatID: destinationChatID
            ),
            repliesGenerator: SuggestedRepliesCoordinator(providerStore: providerStore)
        )
    }

    init(
        importer: any ScreenshotImportProcessing,
        repliesGenerator: any InAppSuggestedRepliesGenerating,
        localization: LocalizationContext = .current
    ) {
        self.importer = importer
        self.repliesGenerator = repliesGenerator
        self.localization = localization
    }

    @discardableResult
    func importScreenshots(
        _ imageDataList: [Data],
        draftingInput: String? = nil
    ) async -> InAppScreenshotImportResult? {
        let images = imageDataList.filter { !$0.isEmpty }
        guard !images.isEmpty else {
            result = nil
            errorMessage = ScreenshotImportError.noImage.localizedDescription
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
        phase = .analyzing
        defer {
            if loadID == currentLoadID {
                isLoading = false
            }
        }

        do {
            let validatedDraftingInput = try DraftingInputLimits.validated(draftingInput)
            let outcome = try await importOperation(traceID)
            guard loadID == currentLoadID else { return nil }
            phase = .generatingReplies

            let replies: SuggestedRepliesOutcome?
            let replyErrorMessage: String?
            if Task.isCancelled {
                replies = nil
                replyErrorMessage = "Reply generation canceled."
            } else {
                do {
                    replies = try await repliesGenerator.generate(
                        chatID: outcome.chatID,
                        draftingInput: validatedDraftingInput,
                        force: true,
                        localization: localization,
                        traceID: traceID
                    )
                    replyErrorMessage = nil
                } catch is CancellationError {
                    replies = nil
                    replyErrorMessage = "Reply generation canceled."
                } catch {
                    replies = nil
                    replyErrorMessage = error.localizedDescription
                }
            }

            guard loadID == currentLoadID else { return nil }

            let result = InAppScreenshotImportResult(
                outcome: outcome,
                replies: replies,
                replyErrorMessage: replyErrorMessage,
                localization: localization
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
