//
//  ChatImportAnalysisDecoder.swift
//  FrameReply
//

import CoreFoundation
import Foundation

nonisolated enum ChatImportAnalysisDecoder {
    static func decode(
        content: String?,
        finishReason: String?,
        isSharedTranscript: Bool,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        try decodeResult(
            content: content,
            finishReason: finishReason,
            isSharedTranscript: isSharedTranscript,
            candidateIDs: candidateIDs
        ).value
    }

    static func decodeResult(
        content: String?,
        finishReason: String?,
        isSharedTranscript: Bool,
        candidateIDs: Set<String>
    ) throws -> StructuredOutputDecodingResult<ChatImportAnalysis> {
        if let finishReason, finishReason != "stop" {
            let kind: StructuredOutputFailureKind =
                finishReason == "length"
                ? .truncatedResponse : .schemaMismatch
            throw StructuredOutputFailure(kind: kind, codingPath: "finish_reason")
        }

        let normalized = try StructuredOutputJSONNormalizer.decodeObject(from: content)
        let root = normalized.object
        var recovered = normalized.recovered
        let knownRootKeys: Set<String> = [
            "conversationTitle", "titleSource", "messages",
            "matchedChatID", "matchConfidence", "userIdentification",
            "conversationKindEvidence"
        ]
        if !Set(root.keys).subtracting(knownRootKeys).isEmpty
            || (isSharedTranscript && root["userIdentification"] != nil)
        {
            recovered = true
        }

        guard let messageValues = root["messages"] as? [Any] else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "messages")
        }
        let messages = try messageValues.enumerated().map { index, value in
            guard let object = value as? [String: Any] else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "messages[\(index)]")
            }
            let knownMessageKeys: Set<String> = [
                "sender", "senderName", "text", "timestampLabel", "outerAlignment",
                "outerAuthorLabel", "senderConfidence", "senderEvidence"
            ]
            if !Set(object.keys).subtracting(knownMessageKeys).isEmpty
                || (isSharedTranscript
                    && (object["outerAlignment"] != nil || object["outerAuthorLabel"] != nil))
            {
                recovered = true
            }
            guard let rawText = object["text"] as? String else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "messages[\(index)].text")
            }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw StructuredOutputFailure(
                    kind: .incompleteMessages, codingPath: "messages[\(index)].text")
            }

            let sender: AnalyzedMessageSender
            let senderWasRecovered: Bool
            if let rawSender = object["sender"] as? String,
                let value = AnalyzedMessageSender(rawValue: rawSender)
            {
                sender = value
                senderWasRecovered = false
            } else {
                sender = .unknown
                senderWasRecovered = true
                recovered = true
            }
            let extractedSenderName = optionalString(
                object["senderName"], recovered: &recovered)
            let senderName =
                isSharedTranscript
                ? normalizedSharedAuthorLabel(extractedSenderName) : extractedSenderName
            let timestampLabel = optionalString(
                object["timestampLabel"], recovered: &recovered)
            let outerAlignment: MessageAlignment
            let outerAuthorLabel: String?
            if isSharedTranscript {
                outerAlignment = .unknown
                outerAuthorLabel = nil
            } else if senderWasRecovered {
                outerAlignment = .unknown
                outerAuthorLabel = nil
            } else {
                if let rawAlignment = object["outerAlignment"] as? String,
                    let value = MessageAlignment(rawValue: rawAlignment)
                {
                    outerAlignment = value
                } else {
                    outerAlignment = .unknown
                    recovered = true
                }
                outerAuthorLabel = optionalString(
                    object["outerAuthorLabel"], recovered: &recovered)
            }
            let senderConfidence =
                senderWasRecovered
                ? 0 : boundedDouble(object["senderConfidence"], recovered: &recovered)
            let senderEvidence: MessageSenderEvidence
            if senderWasRecovered {
                senderEvidence = .insufficient
            } else if let rawEvidence = object["senderEvidence"] as? String,
                let value = MessageSenderEvidence(rawValue: rawEvidence)
            {
                senderEvidence = value
            } else {
                senderEvidence = .insufficient
                recovered = true
            }
            return AnalyzedChatMessage(
                sender: sender,
                senderName: senderName,
                text: text,
                timestampLabel: timestampLabel,
                outerAlignment: outerAlignment,
                outerAuthorLabel: outerAuthorLabel,
                senderConfidence: senderConfidence,
                senderEvidence: senderEvidence
            )
        }

        let conversationTitle = optionalString(
            root["conversationTitle"], recovered: &recovered)
        let conversationKindEvidence = recoveredKindEvidence(
            root["conversationKindEvidence"],
            recovered: &recovered
        )
        let userIdentification: ScreenshotUserIdentification
        if isSharedTranscript {
            userIdentification = .unobservable
        } else {
            userIdentification = recoveredUserIdentification(
                root["userIdentification"], recovered: &recovered)
        }
        let (effectiveConversationKind, validatedConversationKindEvidence) =
            conversationKindResult(
                evidence: conversationKindEvidence,
                messages: messages,
                isSharedTranscript: isSharedTranscript,
                userIdentification: userIdentification
            )
        let titleSource: ChatTitleSource
        if let rawSource = root["titleSource"] as? String,
            let value = ChatTitleSource(rawValue: rawSource)
        {
            titleSource = value
        } else {
            titleSource = .unavailable
            recovered = true
        }
        let matchedChatID: String?
        if let rawID = root["matchedChatID"] as? String, candidateIDs.contains(rawID) {
            matchedChatID = rawID
        } else {
            matchedChatID = nil
            if !(root["matchedChatID"] is NSNull) {
                recovered = true
            }
        }
        let matchConfidence: Double
        if matchedChatID != nil {
            matchConfidence = boundedDouble(root["matchConfidence"], recovered: &recovered)
        } else {
            matchConfidence = 0
            if let value = numericDouble(root["matchConfidence"]), value != 0 {
                recovered = true
            } else if numericDouble(root["matchConfidence"]) == nil {
                recovered = true
            }
        }
        let extractionStatus: ChatExtractionStatus = messages.isEmpty ? .noMessages : .ok

        let validated = try validate(
            ChatImportAnalysis(
                extractionStatus: extractionStatus,
                conversationTitle: conversationTitle,
                messages: messages,
                matchedChatID: matchedChatID,
                matchConfidence: matchConfidence,
                conversationKind: effectiveConversationKind,
                conversationKindEvidence: validatedConversationKindEvidence,
                titleSource: titleSource,
                userIdentification: userIdentification
            ),
            candidateIDs: candidateIDs,
            normalizeVisualUserIdentification: !isSharedTranscript,
            maximumMessageCount: isSharedTranscript
                ? SharedTranscriptInput.maximumEstimatedMessageCount : nil
        )
        return StructuredOutputDecodingResult(value: validated, recovered: recovered)
    }

    static func validate(
        _ input: ChatImportAnalysis,
        candidateIDs: Set<String>,
        normalizeVisualUserIdentification: Bool = true,
        maximumMessageCount: Int? = nil
    ) throws -> ChatImportAnalysis {
        let analysis: ChatImportAnalysis
        if normalizeVisualUserIdentification {
            let normalization = normalize(input)
            analysis = normalization.analysis
            ChatImportDebugLogger.normalization(notes: normalization.notes)
        } else {
            analysis = input
        }

        if let maximumMessageCount, analysis.messages.count > maximumMessageCount {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "messages")
        }
        guard (analysis.extractionStatus == .ok) == !analysis.messages.isEmpty,
            analysis.messages.allSatisfy({
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (0...1).contains($0.senderConfidence)
            })
        else {
            throw StructuredOutputFailure(kind: .incompleteMessages, codingPath: "messages")
        }
        guard (0...1).contains(analysis.matchConfidence) else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "matchConfidence")
        }
        if analysis.matchedChatID == nil, analysis.matchConfidence != 0 {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "matchConfidence")
        }
        if let matchedChatID = analysis.matchedChatID, !candidateIDs.contains(matchedChatID) {
            throw StructuredOutputFailure(kind: .invalidCandidateID, codingPath: "matchedChatID")
        }
        return analysis
    }

    static func normalize(_ analysis: ChatImportAnalysis) -> ChatImportNormalizationResult {
        var notes: [String] = []
        let title = normalizedConversationTitle(analysis.conversationTitle)
        let titleSource: ChatTitleSource
        if analysis.conversationTitle != nil, title == nil {
            notes.append("conversationTitle rejected as system or navigation UI")
            titleSource = .unavailable
        } else {
            titleSource = analysis.titleSource
        }
        let messages = analysis.messages.enumerated().map { index, message in
            let resolved = resolvedSender(
                for: message, identification: analysis.userIdentification,
                kind: analysis.conversationKind)
            guard resolved != message.sender else { return message }

            notes.append(
                "messages[\(index)].sender \(message.sender.rawValue) -> \(resolved.rawValue)")
            return AnalyzedChatMessage(
                sender: resolved,
                senderName: resolved == .user ? nil : message.senderName,
                text: message.text,
                timestampLabel: message.timestampLabel,
                outerAlignment: message.outerAlignment,
                outerAuthorLabel: message.outerAuthorLabel,
                senderConfidence: message.senderConfidence,
                senderEvidence: message.senderEvidence
            )
        }

        return ChatImportNormalizationResult(
            analysis: ChatImportAnalysis(
                extractionStatus: analysis.extractionStatus,
                conversationTitle: title,
                messages: messages,
                matchedChatID: analysis.matchedChatID,
                matchConfidence: analysis.matchConfidence,
                conversationKind: analysis.conversationKind,
                conversationKindEvidence: analysis.conversationKindEvidence,
                titleSource: titleSource,
                userIdentification: analysis.userIdentification
            ),
            notes: notes
        )
    }

    private static func normalizedConversationTitle(_ value: String?) -> String? {
        guard let title = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }
        let compact = title.filter { !$0.isWhitespace }
        if !compact.isEmpty, compact.allSatisfy(\.isNumber) {
            return nil
        }
        let systemOverlayTitles = [
            "back tap", "double tap detected", "triple tap detected",
            "shortcuts", "screenshot", "take screenshot", "framereply"
        ]
        if systemOverlayTitles.contains(title.lowercased()) {
            return nil
        }
        return title
    }

    private static func normalizedSharedAuthorLabel(_ value: String?) -> String? {
        guard var label = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        if label.first == "~" {
            label.removeFirst()
            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return label.isEmpty ? nil : label
    }

    private static func recoveredKindEvidence(
        _ value: Any?,
        recovered: inout Bool
    ) -> ConversationKindEvidence {
        guard let rawValue = value as? String,
            let evidence = ConversationKindEvidence(rawValue: rawValue),
            evidence != .trustedInternal
        else {
            recovered = true
            return .noGroupEvidence
        }
        return evidence
    }

    private static func conversationKindResult(
        evidence: ConversationKindEvidence,
        messages: [AnalyzedChatMessage],
        isSharedTranscript: Bool,
        userIdentification: ScreenshotUserIdentification
    ) -> (ChatConversationKind, ConversationKindEvidence) {
        let explicitLabels = Set(
            messages.compactMap { message in
                let label =
                    isSharedTranscript
                    ? message.senderName
                    : (message.outerAuthorLabel ?? message.senderName)
                return ParticipantLabelNormalizer.key(label)
            }
        )
        let namedAuthorsOppositeUserAlignment = Set(
            messages.compactMap { message -> String? in
                guard !isSharedTranscript,
                    isOppositeUserAlignment(
                        message.outerAlignment,
                        userAlignment: userIdentification.userAlignment)
                else { return nil }
                return ParticipantLabelNormalizer.key(message.outerAuthorLabel)
            }
        )
        let evidenceIsStrong: Bool
        let invalidAuthorCountClaim: Bool
        switch evidence {
        case .explicitGroupLabelOrMemberCount, .groupMembershipChangeEvent:
            evidenceIsStrong = true
            invalidAuthorCountClaim = false
        case .threeOrMoreNamedMessageAuthors:
            evidenceIsStrong = explicitLabels.count >= 3
            invalidAuthorCountClaim = !evidenceIsStrong
        case .twoOrMoreNamedAuthorsOppositeUserAlignment:
            evidenceIsStrong = namedAuthorsOppositeUserAlignment.count >= 2
            invalidAuthorCountClaim = !evidenceIsStrong
        case .groupSuspectedWithoutStructuralProof, .noGroupEvidence, .trustedInternal:
            evidenceIsStrong = false
            invalidAuthorCountClaim = false
        }
        if evidenceIsStrong {
            return (.group, evidence)
        }
        let validatedEvidence: ConversationKindEvidence =
            invalidAuthorCountClaim
            ? .groupSuspectedWithoutStructuralProof : evidence
        return (messages.isEmpty ? .unknown : .direct, validatedEvidence)
    }

    private static func optionalString(_ value: Any?, recovered: inout Bool) -> String? {
        guard value != nil else {
            recovered = true
            return nil
        }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            recovered = true
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            recovered = true
            return nil
        }
        return trimmed
    }

    private static func numericDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    private static func boundedDouble(_ value: Any?, recovered: inout Bool) -> Double {
        guard let number = numericDouble(value), (0...1).contains(number) else {
            recovered = true
            return 0
        }
        return number
    }

    private static func recoveredUserIdentification(
        _ value: Any?,
        recovered: inout Bool
    ) -> ScreenshotUserIdentification {
        guard let object = value as? [String: Any] else {
            recovered = true
            return .unobservable
        }
        let knownKeys: Set<String> = [
            "mode", "userAlignment", "userAuthorLabel"
        ]
        if !Set(object.keys).subtracting(knownKeys).isEmpty {
            recovered = true
        }
        let mode: UserIdentificationMode
        if let rawMode = object["mode"] as? String,
            let value = UserIdentificationMode(rawValue: rawMode)
        {
            mode = value
        } else {
            mode = .unobservable
            recovered = true
        }
        let alignment: MessageAlignment
        if let rawAlignment = object["userAlignment"] as? String,
            let value = MessageAlignment(rawValue: rawAlignment)
        {
            alignment = value
        } else {
            alignment = .unknown
            recovered = true
        }
        let label = optionalString(
            object["userAuthorLabel"], recovered: &recovered)
        return ScreenshotUserIdentification(
            mode: mode,
            userAlignment: alignment,
            userAuthorLabel: label
        )
    }

    private static func userIdentificationDecisions(
        for message: AnalyzedChatMessage,
        identification: ScreenshotUserIdentification
    ) -> [Bool] {
        var decisions: [Bool] = []

        if message.senderEvidence == .messageStatusIndicator {
            decisions.append(true)
        }

        if identification.mode == .opposedAlignment || identification.mode == .mixed,
            identification.userAlignment != .unknown,
            message.outerAlignment != .unknown,
            identification.userAlignment != .fullWidth,
            message.outerAlignment != .fullWidth
        {
            decisions.append(message.outerAlignment == identification.userAlignment)
        }

        if identification.mode == .authorIdentity || identification.mode == .mixed,
            let userLabel = normalizedLabel(identification.userAuthorLabel),
            let outerLabel = normalizedLabel(message.outerAuthorLabel)
        {
            decisions.append(outerLabel == userLabel)
        }

        return decisions
    }

    private static func isOppositeUserAlignment(
        _ messageAlignment: MessageAlignment,
        userAlignment: MessageAlignment
    ) -> Bool {
        switch (messageAlignment, userAlignment) {
        case (.left, .right), (.right, .left):
            true
        default:
            false
        }
    }

    private static func resolvedSender(
        for message: AnalyzedChatMessage,
        identification: ScreenshotUserIdentification,
        kind: ChatConversationKind
    ) -> AnalyzedMessageSender {
        let visibleDecisions = userIdentificationDecisions(
            for: message, identification: identification)

        if visibleDecisions.contains(true), visibleDecisions.contains(false) {
            return .unknown
        }
        if visibleDecisions.allSatisfy({ $0 }), !visibleDecisions.isEmpty {
            return .user
        }
        if visibleDecisions.allSatisfy({ !$0 }), !visibleDecisions.isEmpty {
            return incomingSender(
                reported: message.sender, name: message.senderName ?? message.outerAuthorLabel,
                kind: kind)
        }

        guard identification.mode != .unobservable,
            message.senderEvidence != .insufficient,
            message.senderConfidence >= 0.75
        else {
            return .unknown
        }
        return message.sender
    }

    private static func incomingSender(
        reported: AnalyzedMessageSender,
        name: String?,
        kind: ChatConversationKind
    ) -> AnalyzedMessageSender {
        if kind == .direct {
            return .otherParticipant
        }
        if reported == .otherParticipant || reported == .groupParticipant {
            return reported
        }
        if kind == .group, name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return .groupParticipant
        }
        return .otherParticipant
    }

    private static func normalizedLabel(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }

}

nonisolated struct ChatImportNormalizationResult: Equatable, Sendable {
    let analysis: ChatImportAnalysis
    let notes: [String]
}
