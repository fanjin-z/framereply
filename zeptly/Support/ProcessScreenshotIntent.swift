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
    static func success(_ outcome: ScreenshotImportOutcome) -> ShortcutResponsePresentation {
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
                errorCode: nil
            ),
            dialog: message
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
                errorCode: errorCode
            ),
            dialog: "\(message) Reference \(traceID.diagnosticID)."
        )
    }
}

struct ProcessScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Screenshot"
    static let description = IntentDescription(
        "Extract chat messages from a screenshot, merge them into Zeptly history, and return a JSON result.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Pass the output from Take Screenshot or Get Clipboard.",
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
            let response = ShortcutResponseBuilder.success(outcome)
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
                "Process screenshot in \(.applicationName)",
                "Run screenshot processor in \(.applicationName)"
            ],
            shortTitle: "Process Screenshot",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
