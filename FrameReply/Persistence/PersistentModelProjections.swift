//
//  PersistentModelProjections.swift
//  FrameReply
//

import Foundation
import OSLog
import SwiftUI

extension SelfAliasRecord {
    var normalizedLabel: String {
        IdentityLabelPolicy.normalizedKey(displayLabel) ?? ""
    }
}

extension ChatRecord {
    func displayTitle(locale: Locale = .current) -> String {
        title ?? AppStrings.resolve(AppStrings.Chat.titleFallback, locale: locale)
    }

    func displayPreview(locale: Locale = .current) -> String {
        previewText ?? AppStrings.resolve(AppStrings.Chat.previewFallback, locale: locale)
    }
}

nonisolated enum ChatPresentation {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FrameReply",
        category: "ChatPresentation"
    )

    static func title(for record: ChatRecord?, locale: Locale = .current) -> String {
        title(for: record, provisionalIdentity: nil, locale: locale)
    }

    static func title(
        for record: ChatRecord?,
        provisionalIdentity: ProvisionalIdentityInterpretation?,
        locale: Locale = .current
    ) -> String {
        guard let record else {
            logger.error("Missing chat record while resolving a presentation title")
            return AppStrings.resolve(AppStrings.Chat.titleFallback, locale: locale)
        }
        if let storedTitle = IdentityLabelPolicy.displayLabel(record.title, locale: locale) {
            return storedTitle
        }
        if let inferredTitle = IdentityLabelPolicy.displayLabel(
            provisionalIdentity?.displayTitle,
            locale: locale
        ) {
            return inferredTitle
        }
        return record.displayTitle(locale: locale)
    }
}

extension Chat {
    init(
        record: ChatRecord,
        provisionalIdentity: ProvisionalIdentityInterpretation? = nil
    ) {
        let name = ChatPresentation.title(
            for: record,
            provisionalIdentity: provisionalIdentity
        )
        let preview = record.displayPreview()
        self.init(
            id: record.id,
            name: name,
            preview: preview,
            avatarSymbol: nil,
            initials: Self.initials(for: name),
            gradient: Self.gradient(for: record.id),
            updatedAt: record.updatedAt,
            isProvisional: record.isProvisional
        )
    }

    private static func gradient(for id: String) -> [Color] {
        let gradients: [[Color]] = [
            [FrameReplyColor.peach, FrameReplyColor.primaryContainer],
            [FrameReplyColor.deepNavy, FrameReplyColor.surfaceDim],
            [FrameReplyColor.surfaceVariant, FrameReplyColor.secondaryContainer],
            [FrameReplyColor.secondaryContainer, FrameReplyColor.peach],
            [FrameReplyColor.surfaceVariant, FrameReplyColor.primaryFixed],
            [FrameReplyColor.primaryContainer, FrameReplyColor.deepNavy],
            [FrameReplyColor.surfaceContainerHigh, FrameReplyColor.secondaryContainer]
        ]
        let style = id.unicodeScalars.reduce(UInt(0)) { ($0 &* 31) &+ UInt($1.value) }
        return gradients[Int(style % UInt(gradients.count))]
    }

    private static func initials(for name: String) -> String {
        let components = name.split(whereSeparator: \Character.isWhitespace)
        let value = components.prefix(2).compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "IC" : value.uppercased()
    }
}

extension ChatMessage {
    init(
        record: ChatMessageRecord,
        provisionalIdentity: ProvisionalIdentityInterpretation? = nil
    ) {
        let sender: Sender
        switch provisionalIdentity?.senderKind(for: record) ?? record.senderKind {
        case "user":
            sender = .user
        case "group_participant":
            sender = .groupParticipant(record.senderName ?? "Participant")
        case "unknown":
            sender = .unknown
        default:
            sender = .otherParticipant
        }

        self.init(id: record.id, sender: sender, text: record.text, timeLabel: record.timeLabel)
    }
}

extension ChatContextRecord {
    func value(chatMemories: [ChatMemory] = []) -> ChatContext {
        return ChatContext(
            chatMemories: chatMemories,
            currentInteractionGoal: currentInteractionGoal,
            personaID: personaID,
            personaAssignedAt: personaAssignedAt,
            participantAliases: participantAliases
        )
    }

    func update(from value: ChatContext) {
        currentInteractionGoal = value.currentInteractionGoal
        personaID = value.personaID
        personaAssignedAt = value.personaAssignedAt
        participantAliases = value.participantAliases
    }
}

extension PersonaRecord {
    var value: Persona {
        Persona(
            id: id, name: resolvedName(), summary: resolvedSummary(), symbolName: symbolName,
            accentKey: accentKey, instructions: resolvedInstructions(),
            learningEnabled: learningEnabled,
            sampleCount: sampleCount
        )
    }
}

extension PersonaObservationRecord {
    var value: PersonaObservation {
        return PersonaObservation(
            id: id,
            text: promptText,
            templateID: templateID,
            origin: PersonaObservationOrigin(rawValue: origin) ?? .ai,
            isUserProtected: isUserProtected,
            status: PersonaObservationStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    convenience init(personaID: UUID, value: PersonaObservation) {
        self.init(
            id: value.id, personaID: personaID, text: value.templateID == nil ? value.text : "",
            templateIDRaw: value.templateID?.rawValue,
            origin: value.origin.rawValue, isUserProtected: value.isUserProtected,
            status: value.status.rawValue,
            createdAt: value.createdAt, updatedAt: value.updatedAt
        )
    }
}

extension ChatMemoryRecord {
    var value: ChatMemory {
        return ChatMemory(
            id: id,
            text: text,
            origin: ChatMemoryOrigin(rawValue: origin) ?? .user,
            certainty: ChatMemoryCertainty(rawValue: certainty) ?? .userConfirmed,
            status: ChatMemoryStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    convenience init(chatID: String, value: ChatMemory) {
        self.init(
            id: value.id,
            chatID: chatID,
            text: value.text,
            origin: value.origin.rawValue,
            certainty: value.certainty.rawValue,
            status: value.status.rawValue,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    func update(from value: ChatMemory) {
        text = value.text
        origin = value.origin.rawValue
        certainty = value.certainty.rawValue
        status = value.status.rawValue
        createdAt = value.createdAt
        updatedAt = value.updatedAt
    }
}

extension SuggestedReplyCacheRecord {
    var replies: [String] {
        guard let data = repliesJSON.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
