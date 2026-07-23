//
//  ChatParticipantIdentity.swift
//  FrameReply
//

import Foundation

nonisolated enum IdentityLabelPolicy {
    static func displayLabel(_ value: String?, locale: Locale = .current) -> String? {
        guard let label = ParticipantLabelNormalizer.displayLabel(value),
            !isImportedChatFallback(label, locale: locale)
        else {
            return nil
        }
        return label
    }

    static func normalizedKey(_ value: String?, locale: Locale = .current) -> String? {
        displayLabel(value, locale: locale).flatMap(ParticipantLabelNormalizer.key)
    }

    static func isImportedChatFallback(_ value: String?, locale: Locale = .current) -> Bool {
        guard let key = ParticipantLabelNormalizer.key(value) else { return false }
        return fallbackKeys(locale: locale).contains(key)
    }

    private static func fallbackKeys(locale: Locale) -> Set<String> {
        let localizationIDs =
            Set(Bundle.main.localizations.filter { $0 != "Base" })
            .union([locale.identifier, "en"])
        return Set(
            localizationIDs.compactMap { identifier in
                ParticipantLabelNormalizer.key(
                    AppStrings.resolve(
                        AppStrings.Chat.titleFallback,
                        locale: Locale(identifier: identifier)
                    )
                )
            }
        )
    }
}

nonisolated enum ChatImportReviewError: LocalizedError, Equatable, Sendable {
    case senderIdentityRequired

    var errorDescription: String? {
        switch self {
        case .senderIdentityRequired:
            String(localized: "Choose which sender is you before keeping this chat.")
        }
    }
}

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
        ChatParticipantAlias.normalizedKey(value)
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
            guard let displayLabel = IdentityLabelPolicy.displayLabel(message.senderName),
                let normalizedLabel = IdentityLabelPolicy.normalizedKey(displayLabel)
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
            String(localized: AppStrings.Errors.Chat.senderLabelUnavailable)
        }
    }
}
