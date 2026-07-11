//
//  ChatImportAnalysisDecoder.swift
//  zeptly
//

import Foundation

nonisolated enum ChatImportAnalysisDecoder {
    static func decode(
        content: String?,
        finishReason: String?,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        if finishReason == "length" {
            throw StructuredOutputFailure(kind: .truncatedResponse, codingPath: nil)
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
        try validateVisualContract(jsonObject)

        let analysis: ChatImportAnalysis
        do {
            analysis = try JSONDecoder().decode(ChatImportAnalysis.self, from: data)
        } catch let error as DecodingError {
            throw StructuredOutputFailure(
                kind: .schemaMismatch,
                codingPath: codingPath(for: error)
            )
        } catch {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: nil)
        }

        return try validate(analysis, candidateIDs: candidateIDs)
    }

    static func validate(
        _ analysis: ChatImportAnalysis,
        candidateIDs: Set<String>
    ) throws -> ChatImportAnalysis {
        let normalization = normalize(analysis)
        let analysis = normalization.analysis
        ChatImportDebugLogger.normalization(notes: normalization.notes)

        guard !analysis.messages.isEmpty,
            analysis.messages.allSatisfy({
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (0...1).contains($0.senderConfidence)
                    && ($0.quotedReply?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        != true)
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
        if let bounds = analysis.avatarBounds {
            let values = [bounds.x, bounds.y, bounds.width, bounds.height]
            guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                bounds.x + bounds.width <= 1,
                bounds.y + bounds.height <= 1
            else {
                throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "avatarBounds")
            }
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
                senderEvidence: message.senderEvidence,
                quotedReply: message.quotedReply
            )
        }

        return ChatImportNormalizationResult(
            analysis: ChatImportAnalysis(
                conversationTitle: title,
                messages: messages,
                matchedChatID: analysis.matchedChatID,
                matchConfidence: analysis.matchConfidence,
                conversationKind: analysis.conversationKind,
                titleSource: titleSource,
                avatarBounds: analysis.avatarBounds,
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

    private static func validateVisualContract(_ object: Any) throws {
        guard let root = object as? [String: Any],
            let convention = root["ownershipConvention"] as? [String: Any]
        else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "ownershipConvention")
        }
        for key in ["mode", "screenshotOwnerAlignment", "screenshotOwnerAuthorLabel"]
        where convention.keys.contains(key) == false {
            throw StructuredOutputFailure(
                kind: .schemaMismatch, codingPath: "ownershipConvention.\(key)")
        }
        guard let messages = root["messages"] as? [[String: Any]] else {
            throw StructuredOutputFailure(kind: .schemaMismatch, codingPath: "messages")
        }
        let required = [
            "outerAlignment", "outerAuthorLabel", "senderConfidence", "senderEvidence"
        ]
        for (index, message) in messages.enumerated() {
            for key in required where message.keys.contains(key) == false {
                throw StructuredOutputFailure(
                    kind: .schemaMismatch, codingPath: "messages[\(index)].\(key)")
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
        guard var text = content?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }
        while text.first == "\u{FEFF}" {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard text.hasPrefix("```"), text.hasSuffix("```") else {
            return text
        }
        guard let firstNewline = text.firstIndex(of: "\n") else {
            return text
        }
        let bodyStart = text.index(after: firstNewline)
        let closingFence = text.index(text.endIndex, offsetBy: -3)
        guard bodyStart <= closingFence else {
            return text
        }
        return String(text[bodyStart..<closingFence])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
