//
//  ChatMessageMerger.swift
//  zeptly
//

import Foundation

struct MergeMessage: Equatable {
    let existingID: UUID?
    let senderKind: String
    let senderName: String?
    let text: String
    let normalizedText: String
    let timeLabel: String
    let timestamp: Date?

    init(record: ChatMessageRecord) {
        existingID = record.id
        if record.senderKind == "other" {
            senderKind = ChatImportMatcher.senderKey(.other, name: record.senderName)
        } else {
            senderKind = record.senderKind
        }
        senderName = record.senderName
        text = record.text
        normalizedText = record.normalizedText
        timeLabel = record.timeLabel
        timestamp = record.timestamp
    }

    init(analyzed: AnalyzedChatMessage) {
        existingID = nil
        senderKind = ChatImportMatcher.senderKey(analyzed.sender, name: analyzed.senderName)
        senderName = analyzed.senderName
        text = analyzed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedText = MessageTextNormalizer.normalize(analyzed.text)
        timeLabel = analyzed.timestampLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        timestamp = nil
    }
}

struct ChatMessageMergeResult: Equatable {
    let messages: [MergeMessage]
    let insertedMessageCount: Int
}

enum ChatMessageMerger {
    static func merge(existing: [MergeMessage], imported: [MergeMessage]) -> ChatMessageMergeResult {
        guard !existing.isEmpty else {
            return ChatMessageMergeResult(messages: imported, insertedMessageCount: imported.count)
        }
        guard !imported.isEmpty else {
            return ChatMessageMergeResult(messages: existing, insertedMessageCount: 0)
        }

        let matches = longestCommonSubsequence(existing: existing, imported: imported)
        guard !matches.isEmpty else {
            return ChatMessageMergeResult(
                messages: existing + imported,
                insertedMessageCount: imported.count
            )
        }

        var merged = existing
        let matchedImportedIndices = Set(matches.map(\.importedIndex))
        var insertedCount = 0

        for importedIndex in imported.indices where !matchedImportedIndices.contains(importedIndex) {
            let nextMatch = matches.first(where: { $0.importedIndex > importedIndex })
            if let nextMatch,
                let insertionIndex = merged.firstIndex(where: { $0.existingID == existing[nextMatch.existingIndex].existingID })
            {
                merged.insert(imported[importedIndex], at: insertionIndex)
            } else {
                merged.append(imported[importedIndex])
            }
            insertedCount += 1
        }

        return ChatMessageMergeResult(messages: merged, insertedMessageCount: insertedCount)
    }

    private static func longestCommonSubsequence(
        existing: [MergeMessage],
        imported: [MergeMessage]
    ) -> [MessageMatch] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: imported.count + 1),
            count: existing.count + 1
        )

        for existingIndex in stride(from: existing.count - 1, through: 0, by: -1) {
            for importedIndex in stride(from: imported.count - 1, through: 0, by: -1) {
                if messagesMatch(existing[existingIndex], imported[importedIndex]) {
                    lengths[existingIndex][importedIndex] = lengths[existingIndex + 1][importedIndex + 1] + 1
                } else {
                    lengths[existingIndex][importedIndex] = max(
                        lengths[existingIndex + 1][importedIndex],
                        lengths[existingIndex][importedIndex + 1]
                    )
                }
            }
        }

        var matches: [MessageMatch] = []
        var existingIndex = 0
        var importedIndex = 0
        while existingIndex < existing.count, importedIndex < imported.count {
            if messagesMatch(existing[existingIndex], imported[importedIndex]) {
                matches.append(MessageMatch(existingIndex: existingIndex, importedIndex: importedIndex))
                existingIndex += 1
                importedIndex += 1
            } else if lengths[existingIndex + 1][importedIndex] >= lengths[existingIndex][importedIndex + 1] {
                existingIndex += 1
            } else {
                importedIndex += 1
            }
        }
        return matches
    }

    private static func messagesMatch(_ lhs: MergeMessage, _ rhs: MergeMessage) -> Bool {
        guard lhs.senderKind == rhs.senderKind else {
            return false
        }

        let lhsTime = ChatImportMatcher.normalizedTimestamp(lhs.timeLabel)
        let rhsTime = ChatImportMatcher.normalizedTimestamp(rhs.timeLabel)
        if lhs.normalizedText == rhs.normalizedText {
            if !lhsTime.isEmpty, !rhsTime.isEmpty {
                return lhsTime == rhsTime
            }
            return true
        }

        guard !lhsTime.isEmpty, lhsTime == rhsTime else {
            return false
        }

        return similarity(lhs.normalizedText, rhs.normalizedText) >= 0.97
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1
        }
        let left = Array(lhs)
        let right = Array(rhs)
        let longestCount = max(left.count, right.count)
        guard longestCount > 0 else {
            return 1
        }

        var previous = Array(0...right.count)
        for (leftOffset, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftOffset + 1
            for (rightOffset, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightOffset + 1] = min(
                    current[rightOffset] + 1,
                    previous[rightOffset + 1] + 1,
                    previous[rightOffset] + substitutionCost
                )
            }
            previous = current
        }

        return 1 - (Double(previous[right.count]) / Double(longestCount))
    }
}

private struct MessageMatch {
    let existingIndex: Int
    let importedIndex: Int
}
