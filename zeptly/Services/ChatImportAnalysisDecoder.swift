//
//  ChatImportAnalysisDecoder.swift
//  zeptly
//

import Foundation

nonisolated enum ChatImportAnalysisDecoder {
    static func decode(
        content: String?,
        finishReason: String?,
        isSharedTranscript: Bool,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        if let finishReason, finishReason != "stop" {
            let kind: StructuredOutputFailureKind =
                finishReason == "length"
                ? .truncatedResponse : .schemaMismatch
            throw StructuredOutputFailure(kind: kind, codingPath: "finish_reason")
        }

        let cleaned = clean(content)
        guard !cleaned.isEmpty else {
            throw StructuredOutputFailure(kind: .emptyResponse, codingPath: nil)
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StructuredOutputFailure(kind: .invalidJSON, codingPath: nil)
        }
        try validateContract(jsonObject, isSharedTranscript: isSharedTranscript)

        let analysis: ChatImportAnalysis
        do {
            if isSharedTranscript {
                let shared = try JSONDecoder().decode(SharedTranscriptAnalysis.self, from: data)
                analysis = shared.analysis
            } else {
                analysis = try JSONDecoder().decode(ChatImportAnalysis.self, from: data)
            }
        } catch let error as DecodingError {
            throw StructuredOutputFailure(
                kind: .schemaMismatch,
                codingPath: codingPath(for: error)
            )
        } catch {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: nil)
        }

        return try validate(
            analysis,
            candidateIDs: candidateIDs,
            normalizeVisualOwnership: !isSharedTranscript
        )
    }

    static func validate(
        _ input: ChatImportAnalysis,
        candidateIDs: Set<String>,
        normalizeVisualOwnership: Bool = true
    ) throws -> ChatImportAnalysis {
        let analysis: ChatImportAnalysis
        if normalizeVisualOwnership {
            let normalization = normalize(input)
            analysis = normalization.analysis
            ChatImportDebugLogger.normalization(notes: normalization.notes)
        } else {
            analysis = input
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
                for: message, convention: analysis.ownershipConvention,
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
                titleSource: titleSource,
                ownershipConvention: analysis.ownershipConvention
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
            "shortcuts", "screenshot", "take screenshot", "zeptly"
        ]
        if systemOverlayTitles.contains(title.lowercased()) {
            return nil
        }
        return title
    }

    private static func validateContract(_ object: Any, isSharedTranscript: Bool) throws {
        guard let root = object as? [String: Any] else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "root")
        }
        let common: Set<String> = [
            "extractionStatus", "conversationTitle", "conversationKind", "titleSource",
            "messages", "matchedChatID", "matchConfidence"
        ]
        let expectedRoot = isSharedTranscript ? common : common.union(["ownershipConvention"])
        guard Set(root.keys) == expectedRoot else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "root")
        }
        if !isSharedTranscript {
            guard let convention = root["ownershipConvention"] as? [String: Any],
                Set(convention.keys) == [
                    "mode", "screenshotOwnerAlignment", "screenshotOwnerAuthorLabel"
                ]
            else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "ownershipConvention")
            }
        }
        guard let messages = root["messages"] as? [[String: Any]] else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "messages")
        }
        let required: Set<String> =
            isSharedTranscript
            ? [
                "sender", "senderName", "text", "timestampLabel", "senderConfidence",
                "senderEvidence"
            ]
            : [
                "sender", "senderName", "text", "timestampLabel", "outerAlignment",
                "outerAuthorLabel", "senderConfidence", "senderEvidence"
            ]
        for (index, message) in messages.enumerated() {
            guard Set(message.keys) == required else {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "messages[\(index)]")
            }
        }
    }

    private static func resolvedSender(
        for message: AnalyzedChatMessage,
        convention: MessageOwnershipConvention,
        kind: ChatConversationKind
    ) -> AnalyzedMessageSender {
        var visibleDecisions: [Bool] = []

        if message.senderEvidence == .messageStatusIndicator {
            visibleDecisions.append(true)
        }

        if convention.mode == .opposedAlignment || convention.mode == .mixed,
            convention.screenshotOwnerAlignment != .unknown,
            message.outerAlignment != .unknown,
            convention.screenshotOwnerAlignment != .fullWidth,
            message.outerAlignment != .fullWidth
        {
            visibleDecisions.append(message.outerAlignment == convention.screenshotOwnerAlignment)
        }

        if convention.mode == .authorIdentity || convention.mode == .mixed,
            let screenshotOwnerLabel = normalizedLabel(convention.screenshotOwnerAuthorLabel),
            let outerLabel = normalizedLabel(message.outerAuthorLabel)
        {
            visibleDecisions.append(outerLabel == screenshotOwnerLabel)
        }

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

        guard convention.mode != .unobservable,
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

    private static func clean(_ content: String?) -> String {
        content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func codingPath(for error: DecodingError) -> String? {
        let path: [any CodingKey]
        let appendedKey: (any CodingKey)?
        switch error {
        case .keyNotFound(let key, let context):
            path = context.codingPath
            appendedKey = key
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
            .dataCorrupted(let context):
            path = context.codingPath
            appendedKey = nil
        @unknown default:
            return nil
        }

        let keys = path + (appendedKey.map { [$0] } ?? [])
        guard !keys.isEmpty else { return nil }
        return keys.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
    }
}

nonisolated struct ChatImportNormalizationResult: Equatable, Sendable {
    let analysis: ChatImportAnalysis
    let notes: [String]
}

nonisolated private struct SharedTranscriptAnalysis: Decodable {
    let extractionStatus: ChatExtractionStatus
    let conversationTitle: String?
    let conversationKind: ChatConversationKind
    let titleSource: ChatTitleSource
    let messages: [SharedTranscriptMessage]
    let matchedChatID: String?
    let matchConfidence: Double

    var analysis: ChatImportAnalysis {
        ChatImportAnalysis(
            extractionStatus: extractionStatus,
            conversationTitle: conversationTitle,
            messages: messages.map(\.analyzed),
            matchedChatID: matchedChatID,
            matchConfidence: matchConfidence,
            conversationKind: conversationKind,
            titleSource: titleSource,
            ownershipConvention: .unobservable
        )
    }
}

nonisolated private struct SharedTranscriptMessage: Decodable {
    let sender: AnalyzedMessageSender
    let senderName: String?
    let text: String
    let timestampLabel: String?
    let senderConfidence: Double
    let senderEvidence: MessageSenderEvidence

    var analyzed: AnalyzedChatMessage {
        AnalyzedChatMessage(
            sender: sender,
            senderName: senderName,
            text: text,
            timestampLabel: timestampLabel,
            senderConfidence: senderConfidence,
            senderEvidence: senderEvidence
        )
    }
}
