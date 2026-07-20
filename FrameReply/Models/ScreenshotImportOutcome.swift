//
//  ScreenshotImportOutcome.swift
//  FrameReply
//

import Foundation

nonisolated struct ScreenshotImportOutcome: Equatable, Sendable {
    let chatID: String
    let chatTitle: String?
    let importID: UUID
    let diagnosticID: String
    let matchedExisting: Bool
    let reviewRequired: Bool
    let duplicate: Bool
    let insertedMessageCount: Int
}
