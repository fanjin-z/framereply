//
//  ChatImportAnalysis.swift
//  FrameReply
//

import Foundation

nonisolated struct ChatMatchCandidate: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let participantAliases: [String]
    let recentMessages: [ChatCandidateMessage]

    init(
        id: String,
        name: String,
        participantAliases: [String] = [],
        recentMessages: [ChatCandidateMessage]
    ) {
        self.id = id
        self.name = name
        self.participantAliases = participantAliases
        self.recentMessages = recentMessages
    }
}

nonisolated struct ChatCandidateMessage: Codable, Equatable, Sendable {
    let sender: String
    let text: String
    let timeLabel: String
}

nonisolated struct SharedTranscriptInput: Codable, Equatable, Sendable {
    static let maximumCharacterCount = 8_000
    static let maximumItemCount = 40
    static let maximumEstimatedMessageCount = 25

    let items: [String]

    var characterCount: Int {
        items.reduce(0) { $0 + $1.count }
    }

    var estimatedMessageCount: Int {
        items.reduce(0) { count, item in
            count + max(1, Self.estimatedHeaders(in: item))
        }
    }

    private static func estimatedHeaders(in text: String) -> Int {
        text.components(separatedBy: .newlines).reduce(0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let looksBracketed =
                trimmed.hasPrefix("[") && trimmed.contains("]")
                && trimmed.contains(":")
            let looksDashed =
                trimmed.first?.isNumber == true && trimmed.contains(" - ")
                && trimmed.contains(":")
            return count + ((looksBracketed || looksDashed) ? 1 : 0)
        }
    }
}

nonisolated enum ChatImportPayload: Equatable, Sendable {
    case screenshots([Data])
    case sharedTranscript(SharedTranscriptInput)
}

nonisolated struct ChatImportAnalysisRequest: Equatable, Sendable {
    let payload: ChatImportPayload
    let candidates: [ChatMatchCandidate]
    let traceID: ImportTraceID

    var imageDataList: [Data] {
        guard case .screenshots(let imageDataList) = payload else { return [] }
        return imageDataList
    }

    var sharedTranscript: SharedTranscriptInput? {
        guard case .sharedTranscript(let transcript) = payload else { return nil }
        return transcript
    }

    init(
        imageData: Data,
        candidates: [ChatMatchCandidate],
        traceID: ImportTraceID = ImportTraceID()
    ) {
        self.init(imageDataList: [imageData], candidates: candidates, traceID: traceID)
    }

    init(
        imageDataList: [Data],
        candidates: [ChatMatchCandidate],
        traceID: ImportTraceID = ImportTraceID()
    ) {
        payload = .screenshots(imageDataList)
        self.candidates = candidates
        self.traceID = traceID
    }

    init(
        transcriptItems: [String],
        candidates: [ChatMatchCandidate],
        traceID: ImportTraceID = ImportTraceID()
    ) {
        payload = .sharedTranscript(SharedTranscriptInput(items: transcriptItems))
        self.candidates = candidates
        self.traceID = traceID
    }
}

typealias ChatScreenshotAnalysisRequest = ChatImportAnalysisRequest

nonisolated struct ChatImportAnalysis: Codable, Equatable, Sendable {
    let extractionStatus: ChatExtractionStatus
    let conversationTitle: String?
    let messages: [AnalyzedChatMessage]
    let matchedChatID: String?
    let matchConfidence: Double
    let conversationKind: ChatConversationKind
    let titleSource: ChatTitleSource
    let ownershipConvention: MessageOwnershipConvention

    private enum CodingKeys: String, CodingKey {
        case conversationTitle
        case extractionStatus
        case messages
        case matchedChatID
        case matchConfidence
        case conversationKind
        case titleSource
        case ownershipConvention
    }

    init(
        extractionStatus: ChatExtractionStatus = .ok,
        conversationTitle: String?,
        messages: [AnalyzedChatMessage],
        matchedChatID: String?,
        matchConfidence: Double,
        conversationKind: ChatConversationKind = .direct,
        titleSource: ChatTitleSource = .header,
        ownershipConvention: MessageOwnershipConvention = .unobservable
    ) {
        self.extractionStatus = extractionStatus
        self.conversationTitle = conversationTitle
        self.messages = messages
        self.matchedChatID = matchedChatID
        self.matchConfidence = matchConfidence
        self.conversationKind = conversationKind
        self.titleSource = titleSource
        self.ownershipConvention = ownershipConvention
    }

}

nonisolated enum ChatExtractionStatus: String, Codable, Equatable, Sendable {
    case ok
    case noMessages = "no_messages"
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

nonisolated struct AnalyzedChatMessage: Codable, Equatable, Sendable {
    let sender: AnalyzedMessageSender
    let senderName: String?
    let text: String
    let timestampLabel: String?
    let outerAlignment: MessageAlignment
    let outerAuthorLabel: String?
    let senderConfidence: Double
    let senderEvidence: MessageSenderEvidence

    init(
        sender: AnalyzedMessageSender,
        senderName: String?,
        text: String,
        timestampLabel: String?,
        outerAlignment: MessageAlignment = .unknown,
        outerAuthorLabel: String? = nil,
        senderConfidence: Double = 0,
        senderEvidence: MessageSenderEvidence = .insufficient
    ) {
        self.sender = sender
        self.senderName = senderName
        self.text = text
        self.timestampLabel = timestampLabel
        self.outerAlignment = outerAlignment
        self.outerAuthorLabel = outerAuthorLabel
        self.senderConfidence = senderConfidence
        self.senderEvidence = senderEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case sender
        case senderName
        case text
        case timestampLabel
        case outerAlignment
        case outerAuthorLabel
        case senderConfidence
        case senderEvidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sender = try container.decode(AnalyzedMessageSender.self, forKey: .sender)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        text = try container.decode(String.self, forKey: .text)
        timestampLabel = try container.decodeIfPresent(String.self, forKey: .timestampLabel)
        outerAlignment = try container.decode(MessageAlignment.self, forKey: .outerAlignment)
        outerAuthorLabel = try container.decodeIfPresent(String.self, forKey: .outerAuthorLabel)
        senderConfidence = try container.decode(Double.self, forKey: .senderConfidence)
        senderEvidence = try container.decode(MessageSenderEvidence.self, forKey: .senderEvidence)
    }
}

nonisolated enum AnalyzedMessageSender: String, Codable, Equatable, Sendable {
    case user
    case otherParticipant = "other_participant"
    case groupParticipant = "group_participant"
    case unknown
}

nonisolated enum MessageOwnershipMode: String, Codable, Equatable, Sendable {
    case opposedAlignment = "opposed_alignment"
    case authorIdentity = "author_identity"
    case mixed
    case unobservable
}

nonisolated enum MessageAlignment: String, Codable, Equatable, Sendable {
    case left
    case right
    case fullWidth = "full_width"
    case unknown
}

nonisolated enum MessageSenderEvidence: String, Codable, Equatable, Sendable {
    case messageStatusIndicator = "message_status_indicator"
    case alignmentConvention = "alignment_convention"
    case authorLabel = "author_label"
    case avatar
    case candidateMatch = "candidate_match"
    case mixed
    case insufficient
}

nonisolated struct MessageOwnershipConvention: Codable, Equatable, Sendable {
    let mode: MessageOwnershipMode
    let screenshotOwnerAlignment: MessageAlignment
    let screenshotOwnerAuthorLabel: String?

    static let unobservable = MessageOwnershipConvention(
        mode: .unobservable,
        screenshotOwnerAlignment: .unknown,
        screenshotOwnerAuthorLabel: nil
    )
}
