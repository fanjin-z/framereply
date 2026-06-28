import Foundation

enum ChatMatchDisposition: String, Equatable, Sendable {
    case confirmed
    case review
}

enum AvatarEvidenceLevel: String, Equatable, Sendable {
    case none
    case strong
    case competing
}

enum ChatMatchReason: String, Equatable, Sendable {
    case confirmedDisplayName = "confirmed_display_name"
    case confirmedAvatar = "confirmed_avatar"
    case confirmedTranscript = "confirmed_transcript"
    case lowAIConfidence = "low_ai_confidence"
    case noAICandidate = "no_ai_candidate"
    case unknownAICandidate = "unknown_ai_candidate"
    case displayNameConflict = "display_name_conflict"
    case duplicateDisplayName = "duplicate_display_name"
    case competingAvatar = "competing_avatar"
    case insufficientLocalEvidence = "insufficient_local_evidence"
}

struct ChatMatchDecision: Equatable, Sendable {
    let disposition: ChatMatchDisposition
    let confirmedChatID: String?
    let suggestedChatID: String?
    let aiConfidence: Double
    let avatarEvidence: AvatarEvidenceLevel
    let transcriptEvidence: TranscriptEvidenceLevel
    let reason: ChatMatchReason
}

enum ChatImportMatcher {
    static let automaticMatchThreshold = 0.85

    static func decision(
        analysis: ChatImportAnalysis,
        candidates: [ChatMatchCandidate],
        avatarArtifact: AvatarArtifact? = nil,
        storedAvatars: [StoredAvatarFingerprint] = []
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

        let avatarSimilarities = AvatarIdentityService.similarities(
            artifact: avatarArtifact,
            candidates: storedAvatars
        )
        let strongAvatarID = AvatarIdentityService.uniqueStrongMatch(in: avatarSimilarities)
        let avatarEvidence: AvatarEvidenceLevel
        if strongAvatarID == proposedID {
            avatarEvidence = .strong
        } else if strongAvatarID != nil {
            avatarEvidence = .competing
        } else {
            avatarEvidence = .none
        }

        let imported = analysis.messages.map(transcriptMessage)
        let allCandidateMessages = candidates.map { $0.recentMessages.map(transcriptMessage) }
        let transcript = ChatTranscriptAligner.identityEvidence(
            imported: imported,
            candidate: candidate.recentMessages.map(transcriptMessage),
            allCandidates: allCandidateMessages
        )

        if avatarEvidence == .competing {
            return review(
                analysis,
                suggestedID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .competingAvatar
            )
        }

        let normalizedTitle = MessageTextNormalizer.normalize(analysis.conversationTitle ?? "")
        let normalizedCandidate = MessageTextNormalizer.normalize(candidate.name)
        let titleWasObserved = analysis.titleSource == .header && !normalizedTitle.isEmpty
        let exactName = titleWasObserved && normalizedTitle == normalizedCandidate
        let sameNameCandidates = candidates.filter {
            MessageTextNormalizer.normalize($0.name) == normalizedTitle
        }

        if titleWasObserved, analysis.conversationKind == .direct, !exactName {
            guard avatarEvidence == .strong else {
                return review(
                    analysis,
                    suggestedID: proposedID,
                    avatarEvidence: avatarEvidence,
                    transcriptEvidence: transcript,
                    reason: .displayNameConflict
                )
            }
            return confirmed(
                analysis,
                chatID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .confirmedAvatar
            )
        }

        if exactName, sameNameCandidates.count == 1 {
            return confirmed(
                analysis,
                chatID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .confirmedDisplayName
            )
        }

        if exactName, sameNameCandidates.count > 1 {
            if avatarEvidence == .strong {
                return confirmed(
                    analysis,
                    chatID: proposedID,
                    avatarEvidence: avatarEvidence,
                    transcriptEvidence: transcript,
                    reason: .confirmedAvatar
                )
            }
            if transcript == .strong {
                return confirmed(
                    analysis,
                    chatID: proposedID,
                    avatarEvidence: avatarEvidence,
                    transcriptEvidence: transcript,
                    reason: .confirmedTranscript
                )
            }
            return review(
                analysis,
                suggestedID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .duplicateDisplayName
            )
        }

        if avatarEvidence == .strong {
            return confirmed(
                analysis,
                chatID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .confirmedAvatar
            )
        }
        if transcript == .strong {
            return confirmed(
                analysis,
                chatID: proposedID,
                avatarEvidence: avatarEvidence,
                transcriptEvidence: transcript,
                reason: .confirmedTranscript
            )
        }

        return review(
            analysis,
            suggestedID: proposedID,
            avatarEvidence: avatarEvidence,
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
        case .contact:
            "contact"
        case .other:
            "other:\(MessageTextNormalizer.normalize(name ?? ""))"
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
        avatarEvidence: AvatarEvidenceLevel,
        transcriptEvidence: TranscriptEvidenceLevel,
        reason: ChatMatchReason
    ) -> ChatMatchDecision {
        ChatMatchDecision(
            disposition: .confirmed,
            confirmedChatID: chatID,
            suggestedChatID: chatID,
            aiConfidence: analysis.matchConfidence,
            avatarEvidence: avatarEvidence,
            transcriptEvidence: transcriptEvidence,
            reason: reason
        )
    }

    private static func review(
        _ analysis: ChatImportAnalysis,
        suggestedID: String? = nil,
        avatarEvidence: AvatarEvidenceLevel = .none,
        transcriptEvidence: TranscriptEvidenceLevel = .none,
        reason: ChatMatchReason
    ) -> ChatMatchDecision {
        ChatMatchDecision(
            disposition: .review,
            confirmedChatID: nil,
            suggestedChatID: suggestedID,
            aiConfidence: analysis.matchConfidence,
            avatarEvidence: avatarEvidence,
            transcriptEvidence: transcriptEvidence,
            reason: reason
        )
    }
}
