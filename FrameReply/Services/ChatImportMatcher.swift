import Foundation

nonisolated enum ChatImportMatchDecision: Equatable, Sendable {
    case automatic(String)
    case reviewSuggested(String)
    case none

    var automaticChatID: String? {
        guard case .automatic(let chatID) = self else { return nil }
        return chatID
    }

    var suggestedChatID: String? {
        switch self {
        case .automatic, .none:
            nil
        case .reviewSuggested(let chatID):
            chatID
        }
    }
}

enum ChatImportMatcher {
    static let automaticMatchThreshold = 0.85

    static func decision(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> ChatImportMatchDecision {
        let normalizedTitle =
            IdentityLabelPolicy.displayLabel(analysis.conversationTitle)
            .map(MessageTextNormalizer.normalize) ?? ""
        let titleWasObserved =
            (analysis.titleSource == .header || analysis.titleSource == .participantLabel)
            && !normalizedTitle.isEmpty
        let sameLabelCandidates = titleWasObserved
            ? candidates.filter { $0.identityLabelKeys.contains(normalizedTitle) }
            : []

        guard let proposedID = analysis.matchedChatID,
            let candidate = candidates.first(where: { $0.id == proposedID })
        else {
            if sameLabelCandidates.count == 1, let candidate = sameLabelCandidates.first {
                return .reviewSuggested(candidate.id)
            }
            return .none
        }

        let crossesKnownKinds = !analysis.conversationKind.isCompatible(
            with: candidate.conversationKind)
        let imported = analysis.messages.map {
            transcriptMessage($0, coarseRoles: crossesKnownKinds)
        }
        let allCandidateMessages = candidates.map { candidate in
            candidate.recentMessages.map {
                transcriptMessage($0, coarseRoles: crossesKnownKinds)
            }
        }
        let transcript = ChatTranscriptAligner.identityEvidence(
            imported: imported,
            candidate: candidate.recentMessages.map {
                transcriptMessage($0, coarseRoles: crossesKnownKinds)
            },
            allCandidates: allCandidateMessages
        )

        let exactIdentityLabel =
            titleWasObserved && candidate.identityLabelKeys.contains(normalizedTitle)

        if crossesKnownKinds {
            let mayPromoteDirectCandidate = analysis.conversationKind != .group
                || candidate.conversationKind != .direct
                || analysis.hasStrongGroupEvidence
            if analysis.matchConfidence >= automaticMatchThreshold,
                transcript == .strong,
                mayPromoteDirectCandidate
            {
                return .automatic(proposedID)
            }
            if transcript != .none || exactIdentityLabel {
                return .reviewSuggested(proposedID)
            }
            if sameLabelCandidates.count == 1, let match = sameLabelCandidates.first {
                return .reviewSuggested(match.id)
            }
            return .none
        }

        guard analysis.matchConfidence >= automaticMatchThreshold else {
            if transcript != .none || exactIdentityLabel {
                return .reviewSuggested(proposedID)
            }
            return .none
        }

        if titleWasObserved, analysis.conversationKind == .direct, !exactIdentityLabel {
            if transcript == .strong {
                return .automatic(proposedID)
            }
            return transcript == .weak ? .reviewSuggested(proposedID) : .none
        }

        if exactIdentityLabel, sameLabelCandidates.count == 1 {
            return .automatic(proposedID)
        }

        if exactIdentityLabel, sameLabelCandidates.count > 1 {
            if transcript == .strong {
                return .automatic(proposedID)
            }
            return .none
        }

        if transcript == .strong {
            return .automatic(proposedID)
        }

        return transcript == .weak ? .reviewSuggested(proposedID) : .none
    }

    static func confirmedChatID(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> String? {
        decision(analysis: analysis, candidates: candidates).automaticChatID
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

    private static func transcriptMessage(
        _ message: AnalyzedChatMessage,
        coarseRoles: Bool = false
    ) -> TranscriptMessage {
        TranscriptMessage(
            sender: coarseRoles
                ? coarseSenderKey(senderKey(message.sender, name: message.senderName))
                : senderKey(message.sender, name: message.senderName),
            normalizedText: MessageTextNormalizer.normalize(message.text),
            normalizedTime: normalizedTimestamp(message.timestampLabel)
        )
    }

    private static func transcriptMessage(
        _ message: ChatCandidateMessage,
        coarseRoles: Bool = false
    ) -> TranscriptMessage {
        TranscriptMessage(
            sender: coarseRoles ? coarseSenderKey(message.sender) : message.sender,
            normalizedText: MessageTextNormalizer.normalize(message.text),
            normalizedTime: normalizedTimestamp(message.timeLabel)
        )
    }

    private static func coarseSenderKey(_ value: String) -> String {
        if value == "user" { return "user" }
        if value == "other_participant" || value.hasPrefix("group_participant:") {
            return "other_participant"
        }
        return "unknown"
    }

}

extension ChatMatchCandidate {
    fileprivate var identityLabelKeys: Set<String> {
        Set(
            ([title].compactMap { $0 } + participantAliases)
                .compactMap { IdentityLabelPolicy.displayLabel($0) }
                .map(MessageTextNormalizer.normalize)
        )
    }
}
