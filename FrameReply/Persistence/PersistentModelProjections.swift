//
//  PersistentModelProjections.swift
//  FrameReply
//

import Foundation
import SwiftUI

extension ChatSelfAliasRecord {
    var normalizedLabel: String {
        ParticipantLabelNormalizer.key(displayLabel) ?? ""
    }
}

extension Chat {
    init(record: ChatRecord) {
        self.init(
            id: record.id,
            name: record.name,
            preview: record.preview,
            chipTitle: record.isProvisional ? "Review Import" : "General",
            chipSymbol: record.isProvisional ? "exclamationmark.bubble" : "number",
            avatarSymbol: nil,
            initials: Self.initials(for: record.name),
            gradient: Self.gradient(for: record.id),
            isUnread: false,
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
    init(record: ChatMessageRecord) {
        let sender: Sender
        switch record.senderKind {
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
            id: id, name: name, summary: summary, symbolName: symbolName,
            accentKey: accentKey, instructions: instructions,
            learningEnabled: learningEnabled,
            sampleCount: sampleCount
        )
    }
}

extension PersonaObservationRecord {
    var value: PersonaObservation {
        return PersonaObservation(
            id: id,
            text: text,
            origin: PersonaObservationOrigin(rawValue: origin) ?? .ai,
            isUserProtected: isUserProtected,
            status: PersonaObservationStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    convenience init(personaID: UUID, value: PersonaObservation) {
        self.init(
            id: value.id, personaID: personaID, text: value.text,
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
