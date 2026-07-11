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
        if record.senderKind == "group_participant" {
            senderKind = ChatImportMatcher.senderKey(.groupParticipant, name: record.senderName)
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
    static func merge(existing: [MergeMessage], imported: [MergeMessage]) -> ChatMessageMergeResult
    {
        guard !existing.isEmpty else {
            return ChatMessageMergeResult(messages: imported, insertedMessageCount: imported.count)
        }
        guard !imported.isEmpty else {
            return ChatMessageMergeResult(messages: existing, insertedMessageCount: 0)
        }

        let alignment = ChatTranscriptAligner.align(
            existing: existing.map(\.transcriptMessage),
            imported: imported.map(\.transcriptMessage)
        )
        let matches = alignment.matches
        guard !matches.isEmpty else {
            return ChatMessageMergeResult(
                messages: existing + imported,
                insertedMessageCount: imported.count
            )
        }

        var merged = existing
        let matchedImportedIndices = Set(matches.map(\.importedIndex))
        var existingPositions = Dictionary(uniqueKeysWithValues: existing.indices.map { ($0, $0) })
        var insertedCount = 0

        for importedIndex in imported.indices where !matchedImportedIndices.contains(importedIndex)
        {
            let nextMatch = matches.first(where: { $0.importedIndex > importedIndex })
            if let nextMatch,
                let insertionIndex = existingPositions[nextMatch.existingIndex]
            {
                merged.insert(imported[importedIndex], at: insertionIndex)
                for key in Array(existingPositions.keys)
                where existingPositions[key, default: 0] >= insertionIndex {
                    existingPositions[key, default: 0] += 1
                }
            } else {
                merged.append(imported[importedIndex])
            }
            insertedCount += 1
        }

        return ChatMessageMergeResult(messages: merged, insertedMessageCount: insertedCount)
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        ChatTranscriptAligner.similarity(lhs, rhs)
    }
}

extension MergeMessage {
    fileprivate var transcriptMessage: TranscriptMessage {
        TranscriptMessage(
            sender: senderKind,
            normalizedText: normalizedText,
            normalizedTime: ChatImportMatcher.normalizedTimestamp(timeLabel)
        )
    }
}
