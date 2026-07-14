import Foundation

enum ChatMatchDisposition: String, Equatable, Sendable {
    case confirmed
    case review
}

enum ChatMatchReason: String, Equatable, Sendable {
    case confirmedDisplayName = "confirmed_display_name"
    case confirmedParticipantAlias = "confirmed_participant_alias"
    case confirmedTranscript = "confirmed_transcript"
    case lowAIConfidence = "low_ai_confidence"
    case noAICandidate = "no_ai_candidate"
    case unknownAICandidate = "unknown_ai_candidate"
    case displayNameConflict = "display_name_conflict"
    case duplicateDisplayName = "duplicate_display_name"
    case insufficientLocalEvidence = "insufficient_local_evidence"
}

struct ChatMatchDecision: Equatable, Sendable {
    let disposition: ChatMatchDisposition
    let confirmedChatID: String?
    let suggestedChatID: String?
    let aiConfidence: Double
    let transcriptEvidence: TranscriptEvidenceLevel
    let reason: ChatMatchReason
}

enum ChatImportMatcher {
    static let automaticMatchThreshold = 0.85

    static func decision(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> ChatMatchDecision {
        guard let proposedID = analysis.matchedChatID else {
            return review(analysis, reason: .noAICandidate)
        }
        guard let candidate = candidates.first(where: { $0.id == proposedID }) else {
            return review(analysis, suggestedID: proposedID, reason: .unknownAICandidate)
        }
        guard analysis.matchConfidence >= automaticMatchThreshold else {
            return review(analysis, suggestedID: proposedID, reason: .lowAIConfidence)
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
        let normalizedCandidate = MessageTextNormalizer.normalize(candidate.name)
        let titleWasObserved =
            (analysis.titleSource == .header || analysis.titleSource == .participantLabel)
            && !normalizedTitle.isEmpty
        let exactDisplayName = titleWasObserved && normalizedTitle == normalizedCandidate
        let exactIdentityLabel =
            titleWasObserved && candidate.identityLabelKeys.contains(normalizedTitle)
        let sameLabelCandidates = candidates.filter {
            $0.identityLabelKeys.contains(normalizedTitle)
        }

        if titleWasObserved, analysis.conversationKind == .direct, !exactIdentityLabel {
            if transcript == .strong {
                return confirmed(
                    analysis,
                    chatID: proposedID,
                    transcriptEvidence: transcript,
                    reason: .confirmedTranscript
                )
            }
            return review(
                analysis,
                suggestedID: proposedID,
                transcriptEvidence: transcript,
                reason: .displayNameConflict
            )
        }

        if exactIdentityLabel, sameLabelCandidates.count == 1 {
            return confirmed(
                analysis,
                chatID: proposedID,
                transcriptEvidence: transcript,
                reason: exactDisplayName ? .confirmedDisplayName : .confirmedParticipantAlias
            )
        }

        if exactIdentityLabel, sameLabelCandidates.count > 1 {
            if transcript == .strong {
                return confirmed(
                    analysis,
                    chatID: proposedID,
                    transcriptEvidence: transcript,
                    reason: .confirmedTranscript
                )
            }
            return review(
                analysis,
                suggestedID: proposedID,
                transcriptEvidence: transcript,
                reason: .duplicateDisplayName
            )
        }

        if transcript == .strong {
            return confirmed(
                analysis,
                chatID: proposedID,
                transcriptEvidence: transcript,
                reason: .confirmedTranscript
            )
        }

        return review(
            analysis,
            suggestedID: proposedID,
            transcriptEvidence: transcript,
            reason: .insufficientLocalEvidence
        )
    }

    static func confirmedChatID(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate]
    ) -> String? {
        decision(analysis: analysis, candidates: candidates).confirmedChatID
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

    private static func confirmed(
        _ analysis: ChatImportAnalysis,
        chatID: String,
        transcriptEvidence: TranscriptEvidenceLevel,
        reason: ChatMatchReason
    ) -> ChatMatchDecision {
        ChatMatchDecision(
            disposition: .confirmed,
            confirmedChatID: chatID,
            suggestedChatID: chatID,
            aiConfidence: analysis.matchConfidence,
            transcriptEvidence: transcriptEvidence,
            reason: reason
        )
    }

    private static func review(
        _ analysis: ChatImportAnalysis,
        suggestedID: String? = nil,
        transcriptEvidence: TranscriptEvidenceLevel = .none,
        reason: ChatMatchReason
    ) -> ChatMatchDecision {
        ChatMatchDecision(
            disposition: .review,
            confirmedChatID: nil,
            suggestedChatID: suggestedID,
            aiConfidence: analysis.matchConfidence,
            transcriptEvidence: transcriptEvidence,
            reason: reason
        )
    }
}

extension ChatMatchCandidate {
    fileprivate var identityLabelKeys: Set<String> {
        Set(([name] + participantAliases).map(MessageTextNormalizer.normalize))
    }
}
