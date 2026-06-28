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
    let imageData: Data
    let candidates: [ChatMatchCandidate]
    let traceID: ImportTraceID

    init(
        imageData: Data,
        candidates: [ChatMatchCandidate],
        traceID: ImportTraceID = ImportTraceID()
    ) {
        self.imageData = imageData
        self.candidates = candidates
        self.traceID = traceID
    }
}

nonisolated struct ChatImportAnalysis: Codable, Equatable, Sendable {
    let conversationTitle: String?
    let participants: [String]
    let messages: [AnalyzedChatMessage]
    let matchedChatID: String?
    let matchConfidence: Double
    let sourceApp: String?
    let conversationKind: ChatConversationKind
    let titleSource: ChatTitleSource
    let avatarBounds: NormalizedAvatarBounds?
    let matchBasis: ChatMatchBasis

    private enum CodingKeys: String, CodingKey {
        case conversationTitle
        case participants
        case messages
        case matchedChatID
        case matchConfidence
        case sourceApp
        case conversationKind
        case titleSource
        case avatarBounds
        case matchBasis
    }

    init(
        conversationTitle: String?,
        participants: [String],
        messages: [AnalyzedChatMessage],
        matchedChatID: String?,
        matchConfidence: Double,
        sourceApp: String? = nil,
        conversationKind: ChatConversationKind = .direct,
        titleSource: ChatTitleSource = .header,
        avatarBounds: NormalizedAvatarBounds? = nil,
        matchBasis: ChatMatchBasis = .insufficientEvidence
    ) {
        self.conversationTitle = conversationTitle
        self.participants = participants
        self.messages = messages
        self.matchedChatID = matchedChatID
        self.matchConfidence = matchConfidence
        self.sourceApp = sourceApp
        self.conversationKind = conversationKind
        self.titleSource = titleSource
        self.avatarBounds = avatarBounds
        self.matchBasis = matchBasis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Transcript messages remain strict. Identity and selection metadata degrades
        // conservatively when a JSON-mode provider omits or misspells a value.
        conversationTitle = try? container.decode(String.self, forKey: .conversationTitle)
        participants = (try? container.decode([String].self, forKey: .participants)) ?? []
        messages = try container.decode([AnalyzedChatMessage].self, forKey: .messages)
        matchedChatID = try? container.decode(String.self, forKey: .matchedChatID)
        matchConfidence = (try? container.decode(Double.self, forKey: .matchConfidence)) ?? 0
        sourceApp = try? container.decode(String.self, forKey: .sourceApp)
        conversationKind = (try? container.decode(ChatConversationKind.self, forKey: .conversationKind))
            ?? .unknown
        titleSource = (try? container.decode(ChatTitleSource.self, forKey: .titleSource))
            ?? .unavailable
        avatarBounds = try? container.decode(NormalizedAvatarBounds.self, forKey: .avatarBounds)
        matchBasis = (try? container.decode(ChatMatchBasis.self, forKey: .matchBasis))
            ?? .insufficientEvidence
    }

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

nonisolated enum ChatConversationKind: String, Codable, Equatable, Sendable {
    case direct
    case group
    case unknown
}

nonisolated enum ChatTitleSource: String, Codable, Equatable, Sendable {
    case header
    case participantLabel = "participant_label"
    case unavailable
}

nonisolated enum ChatMatchBasis: String, Codable, Equatable, Sendable {
    case displayName = "display_name"
    case groupIdentity = "group_identity"
    case distinctiveMessages = "distinctive_messages"
    case mixedEvidence = "mixed_evidence"
    case identityConflict = "identity_conflict"
    case insufficientEvidence = "insufficient_evidence"
}

/// Unit coordinates use a top-left origin and describe the visible header avatar.
nonisolated struct NormalizedAvatarBounds: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
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
