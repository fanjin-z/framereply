//
//  ChatImportMatcher.swift
//  zeptly
//

import Foundation

enum ChatImportMatcher {
    static let automaticMatchThreshold = 0.85

    static func confirmedChatID(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> String? {
        guard analysis.matchConfidence >= automaticMatchThreshold,
            let proposedID = analysis.matchedChatID,
            let candidate = candidates.first(where: { $0.id == proposedID })
        else {
            return nil
        }

        if hasNameEvidence(analysis: analysis, candidate: candidate)
            || hasMessageEvidence(analysis: analysis, candidate: candidate)
        {
            return candidate.id
        }

        return nil
    }

    private static func hasNameEvidence(
        analysis: ChatImportAnalysis,
        candidate: ChatMatchCandidate
    ) -> Bool {
        let candidateName = MessageTextNormalizer.normalize(candidate.name)
        let names = [analysis.conversationTitle].compactMap { $0 } + analysis.participants
        return names.contains { MessageTextNormalizer.normalize($0) == candidateName }
    }

    private static func hasMessageEvidence(
        analysis: ChatImportAnalysis,
        candidate: ChatMatchCandidate
    ) -> Bool {
        let imported = analysis.messages.map { message in
            EvidenceMessage(
                sender: senderKey(message.sender, name: message.senderName),
                text: MessageTextNormalizer.normalize(message.text),
                timeLabel: normalizedTimestamp(message.timestampLabel)
            )
        }
        let existing = candidate.recentMessages.map { message in
            EvidenceMessage(
                sender: message.sender,
                text: MessageTextNormalizer.normalize(message.text),
                timeLabel: normalizedTimestamp(message.timeLabel)
            )
        }

        var consecutiveMatches = 0
        for importedStart in imported.indices {
            for existingStart in existing.indices {
                var importedIndex = importedStart
                var existingIndex = existingStart
                var currentMatches = 0
                while importedIndex < imported.count,
                    existingIndex < existing.count,
                    imported[importedIndex].sender == existing[existingIndex].sender,
                    imported[importedIndex].text == existing[existingIndex].text
                {
                    let importedTime = imported[importedIndex].timeLabel
                    let existingTime = existing[existingIndex].timeLabel
                    if currentMatches == 0,
                        !importedTime.isEmpty,
                        importedTime == existingTime
                    {
                        return true
                    }
                    currentMatches += 1
                    consecutiveMatches = max(consecutiveMatches, currentMatches)
                    importedIndex += 1
                    existingIndex += 1
                }
            }
        }
        return consecutiveMatches >= 2
    }

    static func senderKey(_ sender: AnalyzedMessageSender, name: String?) -> String {
        switch sender {
        case .user:
            "user"
        case .contact:
            "contact"
        case .other:
            "other:\(MessageTextNormalizer.normalize(name ?? ""))"
        }
    }

    static func normalizedTimestamp(_ timestamp: String?) -> String {
        MessageTextNormalizer.normalize(timestamp ?? "")
    }
}

private struct EvidenceMessage {
    let sender: String
    let text: String
    let timeLabel: String
}
