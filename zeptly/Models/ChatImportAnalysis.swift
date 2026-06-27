//
//  ChatImportAnalysis.swift
//  zeptly
//

import Foundation

nonisolated struct ChatMatchCandidate: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let recentMessages: [ChatCandidateMessage]
}

nonisolated struct ChatCandidateMessage: Codable, Equatable, Sendable {
    let sender: String
    let text: String
    let timeLabel: String
}

nonisolated struct ChatScreenshotAnalysisRequest: Equatable, Sendable {
    let document: OCRDocument
    let candidates: [ChatMatchCandidate]
}

nonisolated struct ChatImportAnalysis: Codable, Equatable, Sendable {
    let conversationTitle: String?
    let participants: [String]
    let messages: [AnalyzedChatMessage]
    let matchedChatID: String?
    let matchConfidence: Double

    func validated(candidateIDs: Set<String>) throws -> ChatImportAnalysis {
        guard !messages.isEmpty,
            messages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            (0...1).contains(matchConfidence)
        else {
            throw ProviderConnectionError.invalidResponse("The provider returned incomplete chat data.")
        }

        if let matchedChatID, !candidateIDs.contains(matchedChatID) {
            throw ProviderConnectionError.invalidResponse("The provider returned an unknown chat match.")
        }

        return self
    }
}

nonisolated struct AnalyzedChatMessage: Codable, Equatable, Sendable {
    let sender: AnalyzedMessageSender
    let senderName: String?
    let text: String
    let timestampLabel: String?
}

nonisolated enum AnalyzedMessageSender: String, Codable, Equatable, Sendable {
    case user
    case contact
    case other
}
