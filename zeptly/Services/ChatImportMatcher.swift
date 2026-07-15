import Foundation

enum ChatImportMatcher {
    static let automaticMatchThreshold = 0.85

    static func confirmedChatID(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> String? {
        guard let proposedID = analysis.matchedChatID else {
            return nil
        }
        guard let candidate = candidates.first(where: { $0.id == proposedID }) else {
            return nil
        }
        guard analysis.matchConfidence >= automaticMatchThreshold else {
            return nil
        }

        let imported = analysis.messages.map { transcriptMessage($0) }
        let allCandidateMessages = candidates.map { candidate in
            candidate.recentMessages.map { transcriptMessage($0) }
        }
        let transcript = ChatTranscriptAligner.identityEvidence(
            imported: imported,
            candidate: candidate.recentMessages.map { transcriptMessage($0) },
            allCandidates: allCandidateMessages
        )

        let normalizedTitle = MessageTextNormalizer.normalize(analysis.conversationTitle ?? "")
        let titleWasObserved =
            (analysis.titleSource == .header || analysis.titleSource == .participantLabel)
            && !normalizedTitle.isEmpty
        let exactIdentityLabel =
            titleWasObserved && candidate.identityLabelKeys.contains(normalizedTitle)
        let sameLabelCandidates = candidates.filter {
            $0.identityLabelKeys.contains(normalizedTitle)
        }

        if titleWasObserved, analysis.conversationKind == .direct, !exactIdentityLabel {
            if transcript == .strong {
                return proposedID
            }
            return nil
        }

        if exactIdentityLabel, sameLabelCandidates.count == 1 {
            return proposedID
        }

        if exactIdentityLabel, sameLabelCandidates.count > 1 {
            if transcript == .strong {
                return proposedID
            }
            return nil
        }

        if transcript == .strong {
            return proposedID
        }

        return nil
    }

    static func senderKey(_ sender: AnalyzedMessageSender, name: String?) -> String {
        switch sender {
        case .user:
            "user"
        case .otherParticipant:
            "other_participant"
        case .groupParticipant:
            "group_participant:\(MessageTextNormalizer.normalize(name ?? ""))"
        case .unknown:
            "unknown"
        }
    }

    static func normalizedTimestamp(_ timestamp: String?) -> String {
        MessageTextNormalizer.normalize(timestamp ?? "")
    }

    private static func transcriptMessage(_ message: AnalyzedChatMessage) -> TranscriptMessage {
        TranscriptMessage(
            sender: senderKey(message.sender, name: message.senderName),
            normalizedText: MessageTextNormalizer.normalize(message.text),
            normalizedTime: normalizedTimestamp(message.timestampLabel)
        )
    }

    private static func transcriptMessage(_ message: ChatCandidateMessage) -> TranscriptMessage {
        TranscriptMessage(
            sender: message.sender,
            normalizedText: MessageTextNormalizer.normalize(message.text),
            normalizedTime: normalizedTimestamp(message.timeLabel)
        )
    }

}

extension ChatMatchCandidate {
    fileprivate var identityLabelKeys: Set<String> {
        Set(([name] + participantAliases).map(MessageTextNormalizer.normalize))
    }
}
