//
//  ChatParticipantIdentity.swift
//  zeptly
//

import Foundation

nonisolated enum ParticipantLabelNormalizer {
    static func displayLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.precomposedStringWithCanonicalMapping
        let collapsed =
            normalized
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func key(_ value: String?) -> String? {
        displayLabel(value)
    }
}

struct UnknownSenderLabelGroup: Identifiable, Equatable {
    let chatID: String
    let normalizedLabel: String
    let displayLabel: String
    let messageIDs: [UUID]
    let sampleMessages: [String]

    var id: String {
        "\(chatID)\u{1F}\(normalizedLabel)"
    }

    @MainActor
    static func make(from messages: [ChatMessageRecord]) -> [UnknownSenderLabelGroup] {
        struct Accumulator {
            let chatID: String
            let normalizedLabel: String
            let displayLabel: String
            var messageIDs: [UUID]
            var sampleMessages: [String]
        }

        var order: [String] = []
        var accumulators: [String: Accumulator] = [:]

        for message in messages where message.senderKind == "unknown" {
            guard let displayLabel = ParticipantLabelNormalizer.displayLabel(message.senderName),
                let normalizedLabel = ParticipantLabelNormalizer.key(displayLabel)
            else {
                continue
            }
            let id = "\(message.chatID)\u{1F}\(normalizedLabel)"
            if var existing = accumulators[id] {
                existing.messageIDs.append(message.id)
                if existing.sampleMessages.count < 2 {
                    existing.sampleMessages.append(message.text)
                }
                accumulators[id] = existing
            } else {
                order.append(id)
                accumulators[id] = Accumulator(
                    chatID: message.chatID,
                    normalizedLabel: normalizedLabel,
                    displayLabel: displayLabel,
                    messageIDs: [message.id],
                    sampleMessages: [message.text]
                )
            }
        }

        return order.compactMap { id in
            guard let value = accumulators[id] else { return nil }
            return UnknownSenderLabelGroup(
                chatID: value.chatID,
                normalizedLabel: value.normalizedLabel,
                displayLabel: value.displayLabel,
                messageIDs: value.messageIDs,
                sampleMessages: value.sampleMessages
            )
        }
    }
}

struct SenderLabelResolutionOutcome: Equatable {
    let resolvedUserCount: Int
    let resolvedOtherCount: Int
    let remainingUnknownCount: Int
    let renamedChat: Bool
}

enum SenderLabelResolutionError: LocalizedError {
    case labelUnavailable

    var errorDescription: String? {
        switch self {
        case .labelUnavailable:
            "That sender label is no longer available. Reopen the review and try again."
        }
    }
}
