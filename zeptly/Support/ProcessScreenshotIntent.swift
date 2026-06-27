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

nonisolated enum ShortcutResponseStatus: String, Codable, Sendable {
    case success
    case fail
}

nonisolated struct ShortcutResponsePayload: Codable, Sendable {
    let status: ShortcutResponseStatus
    let message: String
    let chatID: String?
    let importID: UUID?
    let matchedExisting: Bool?
    let reviewRequired: Bool?
    let duplicate: Bool?
    let insertedMessageCount: Int?
    let errorCode: String?
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

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let screenshot else {
            return .result(
                value: makePayload(
                    status: .fail,
                    message: "No image input was provided.",
                    errorCode: "no_image"
                )
            )
        }

        guard isImageFile(screenshot) else {
            let typeIdentifier = screenshot.type?.identifier ?? "unknown"
            let details =
                "input is not an image (type: \(typeIdentifier), filename: \(screenshot.filename), bytes: \(screenshot.data.count))"
            return .result(
                value: makePayload(
                    status: .fail,
                    message: details,
                    errorCode: "invalid_image"
                )
            )
        }

        do {
            let outcome = try await ScreenshotImportCoordinator().process(imageData: screenshot.data)
            let message = outcome.reviewRequired
                ? "Chat imported and queued for review."
                : "Chat history imported."
            return .result(value: makePayload(status: .success, message: message, outcome: outcome))
        } catch let error as ScreenshotImportError {
            return .result(
                value: makePayload(
                    status: .fail,
                    message: error.localizedDescription,
                    errorCode: error.code
                )
            )
        } catch let error as ScreenshotOCRError {
            return .result(
                value: makePayload(
                    status: .fail,
                    message: error.localizedDescription,
                    errorCode: "ocr_failed"
                )
            )
        } catch let error as ProviderConnectionError {
            return .result(
                value: makePayload(
                    status: .fail,
                    message: error.localizedDescription,
                    errorCode: "provider_error"
                )
            )
        } catch {
            return .result(
                value: makePayload(
                    status: .fail,
                    message: "The chat history could not be saved.",
                    errorCode: "import_failed"
                )
            )
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

    private func makePayload(
        status: ShortcutResponseStatus,
        message: String,
        outcome: ScreenshotImportOutcome? = nil,
        errorCode: String? = nil
    ) -> String {
        let payload = ShortcutResponsePayload(
            status: status,
            message: message,
            chatID: outcome?.chatID,
            importID: outcome?.importID,
            matchedExisting: outcome?.matchedExisting,
            reviewRequired: outcome?.reviewRequired,
            duplicate: outcome?.duplicate,
            insertedMessageCount: outcome?.insertedMessageCount,
            errorCode: errorCode
        )
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"status\":\"fail\",\"message\":\"failed to encode response\"}"
        }

        return json
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
