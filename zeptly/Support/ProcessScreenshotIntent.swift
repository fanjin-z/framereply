//
//  ProcessScreenshotIntent.swift
//  zeptly
//
//  Created by GitHub Copilot.
//

import AppIntents
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ShortcutResponseStatus: String, Codable, Equatable, Sendable {
    case success
    case fail
}

nonisolated enum ShortcutReplyStatus: String, Codable, Equatable, Sendable {
    case generated
    case cached
    case failed
}

nonisolated struct ShortcutResponsePayload: Codable, Equatable, Sendable {
    let status: ShortcutResponseStatus
    let message: String
    let diagnosticID: String
    let chatID: String?
    let chatName: String?
    let importID: UUID?
    let matchedExisting: Bool?
    let reviewRequired: Bool?
    let duplicate: Bool?
    let insertedMessageCount: Int?
    let errorCode: String?
    let suggestedReplies: [String]?
    let replyStatus: ShortcutReplyStatus?
    let replyErrorCode: String?

    init(
        status: ShortcutResponseStatus,
        message: String,
        diagnosticID: String,
        chatID: String?,
        chatName: String?,
        importID: UUID?,
        matchedExisting: Bool?,
        reviewRequired: Bool?,
        duplicate: Bool?,
        insertedMessageCount: Int?,
        errorCode: String?,
        suggestedReplies: [String]? = nil,
        replyStatus: ShortcutReplyStatus? = nil,
        replyErrorCode: String? = nil
    ) {
        self.status = status
        self.message = message
        self.diagnosticID = diagnosticID
        self.chatID = chatID
        self.chatName = chatName
        self.importID = importID
        self.matchedExisting = matchedExisting
        self.reviewRequired = reviewRequired
        self.duplicate = duplicate
        self.insertedMessageCount = insertedMessageCount
        self.errorCode = errorCode
        self.suggestedReplies = suggestedReplies
        self.replyStatus = replyStatus
        self.replyErrorCode = replyErrorCode
    }
}

nonisolated struct ShortcutResponsePresentation: Equatable, Sendable {
    let payload: ShortcutResponsePayload
    let dialog: String

    var json: String {
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"status\":\"fail\",\"message\":\"failed to encode response\"}"
        }
        return json
    }
}

nonisolated enum ShortcutResponseBuilder {
    static func success(
        _ outcome: ScreenshotImportOutcome,
        repliesOutcome: SuggestedRepliesOutcome? = nil,
        replyErrorCode: String? = nil
    ) -> ShortcutResponsePresentation {
        let count = outcome.insertedMessageCount
        let noun = count == 1 ? "message" : "messages"
        let message: String
        if outcome.duplicate {
            message = "No new messages found in \(outcome.chatName)."
        } else if outcome.reviewRequired {
            message = "Imported \(count) \(noun) as \(outcome.chatName). Review it in Zeptly."
        } else {
            message = "Added \(count) new \(noun) to \(outcome.chatName)."
        }

        let replies = repliesOutcome?.replies
        let replyStatus = repliesOutcome.map {
            switch $0.source {
            case .generated: ShortcutReplyStatus.generated
            case .cached: ShortcutReplyStatus.cached
            }
        } ?? .failed
        let dialog: String
        if let replies, replies.count == 2 {
            dialog = "\(message)\n\nSuggested replies:\n1. \(replies[0])\n2. \(replies[1])"
        } else {
            dialog = "\(message) Suggested replies are unavailable; open Zeptly to retry."
        }

        return ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .success,
                message: message,
                diagnosticID: outcome.diagnosticID,
                chatID: outcome.chatID,
                chatName: outcome.chatName,
                importID: outcome.importID,
                matchedExisting: outcome.matchedExisting,
                reviewRequired: outcome.reviewRequired,
                duplicate: outcome.duplicate,
                insertedMessageCount: count,
                errorCode: nil,
                suggestedReplies: replies,
                replyStatus: replyStatus,
                replyErrorCode: repliesOutcome == nil ? (replyErrorCode ?? "reply_generation_failed") : nil
            ),
            dialog: dialog
        )
    }

    static func failure(
        message: String,
        errorCode: String,
        traceID: ImportTraceID
    ) -> ShortcutResponsePresentation {
        ShortcutResponsePresentation(
            payload: ShortcutResponsePayload(
                status: .fail,
                message: message,
                diagnosticID: traceID.diagnosticID,
                chatID: nil,
                chatName: nil,
                importID: nil,
                matchedExisting: nil,
                reviewRequired: nil,
                duplicate: nil,
                insertedMessageCount: nil,
                errorCode: errorCode,
                suggestedReplies: nil,
                replyStatus: nil,
                replyErrorCode: nil
            ),
            dialog: "\(message) Reference \(traceID.diagnosticID)."
        )
    }
}

struct ProcessScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Chat Screenshot"
    static let description = IntentDescription(
        "Adds visible messages to Zeptly and suggests two replies. The screenshot itself isn't saved.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Pass an image, such as the output from Take Screenshot or Get Clipboard.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let traceID = ImportTraceID()
        let eventReporter = OSLogImportEventReporter()
        guard let screenshot else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "no_image"))
            let response = ShortcutResponseBuilder.failure(
                message: "No image input was provided.",
                errorCode: "no_image",
                traceID: traceID
            )
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        }

        guard isImageFile(screenshot) else {
            eventReporter.record(.importFailed(traceID: traceID, stage: .shortcut, errorCode: "invalid_image"))
            let response = ShortcutResponseBuilder.failure(
                message: "The provided file is not a readable image.",
                errorCode: "invalid_image",
                traceID: traceID
            )
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        }

        do {
            let outcome = try await ScreenshotImportCoordinator().process(
                imageData: screenshot.data,
                traceID: traceID
            )
            let response: ShortcutResponsePresentation
            do {
                let replies = try await SuggestedRepliesCoordinator().generate(
                    chatID: outcome.chatID,
                    traceID: traceID
                )
                response = ShortcutResponseBuilder.success(outcome, repliesOutcome: replies)
            } catch let error as SuggestedRepliesError {
                response = ShortcutResponseBuilder.success(outcome, replyErrorCode: error.code)
            } catch let error as ProviderConnectionError {
                response = ShortcutResponseBuilder.success(outcome, replyErrorCode: error.shortcutErrorCode)
            } catch {
                response = ShortcutResponseBuilder.success(outcome, replyErrorCode: "reply_generation_failed")
            }
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        } catch let error as ScreenshotImportError {
            let response = ShortcutResponseBuilder.failure(
                message: error.localizedDescription,
                errorCode: error.code,
                traceID: traceID
            )
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        } catch let error as ProviderConnectionError {
            let response = ShortcutResponseBuilder.failure(
                message: error.localizedDescription,
                errorCode: error.shortcutErrorCode,
                traceID: traceID
            )
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        } catch {
            let response = ShortcutResponseBuilder.failure(
                message: "The chat history could not be saved.",
                errorCode: "import_failed",
                traceID: traceID
            )
            return .result(value: response.json, dialog: IntentDialog(stringLiteral: response.dialog))
        }
    }

    private func isImageFile(_ file: IntentFile) -> Bool {
        if let type = file.type {
            return type.conforms(to: .image)
        }

        let fileExtension = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
        if !fileExtension.isEmpty,
            let inferredType = UTType(filenameExtension: fileExtension),
            inferredType.conforms(to: .image)
        {
            return true
        }

        guard let source = CGImageSourceCreateWithData(file.data as CFData, nil) else {
            return false
        }

        if let typeIdentifier = CGImageSourceGetType(source) as String?,
            let sourceType = UTType(typeIdentifier),
            sourceType.conforms(to: .image)
        {
            return true
        }

        if CGImageSourceGetCount(source) > 0 {
            return true
        }

        return !file.data.isEmpty
    }
}

struct ZeptlyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ProcessScreenshotIntent(),
            phrases: [
                "Process chat screenshot in \(.applicationName)",
                "Process my chat screenshot with \(.applicationName)"
            ],
            shortTitle: "Process Chat Screenshot",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
