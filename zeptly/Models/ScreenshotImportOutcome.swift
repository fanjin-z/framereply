//
//  ScreenshotImportOutcome.swift
//  zeptly
//

import Foundation

nonisolated struct ScreenshotImportOutcome: Equatable, Sendable {
    let chatID: String
    let importID: UUID
    let matchedExisting: Bool
    let reviewRequired: Bool
    let duplicate: Bool
    let insertedMessageCount: Int
}
