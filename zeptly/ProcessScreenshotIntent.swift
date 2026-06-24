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

nonisolated private enum ShortcutResponseStatus: String, Codable, Sendable {
    case success
    case fail
}

nonisolated private struct ShortcutResponsePayload: Codable, Sendable {
    let status: ShortcutResponseStatus
    let message: String
}

struct ProcessScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Screenshot"
    static let description = IntentDescription(
        "Validate screenshot input and return a JSON status payload for the next Shortcut step.")
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
            return .result(value: makePayload(status: .fail, message: "no image input"))
        }

        guard isImageFile(screenshot) else {
            let typeIdentifier = screenshot.type?.identifier ?? "unknown"
            let details =
                "input is not an image (type: \(typeIdentifier), filename: \(screenshot.filename), bytes: \(screenshot.data.count))"
            return .result(value: makePayload(status: .fail, message: details))
        }

        return .result(value: makePayload(status: .success, message: "hello world"))
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

    private func makePayload(status: ShortcutResponseStatus, message: String) -> String {
        let payload = ShortcutResponsePayload(status: status, message: message)
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
