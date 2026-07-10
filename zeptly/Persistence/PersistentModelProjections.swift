//
//  PersistentModelProjections.swift
//  zeptly
//

import Foundation
import SwiftUI

extension Chat {
    init(record: ChatRecord) {
        self.init(
            id: record.id,
            name: record.name,
            preview: record.preview,
            chipTitle: record.chipTitle,
            chipSymbol: record.chipSymbol,
            avatarSymbol: record.avatarSymbol,
            avatarData: record.avatarData,
            initials: record.initials,
            gradient: Self.gradient(for: record.appearanceStyle),
            isUnread: record.isUnread,
            contactContext: nil,
            isProvisional: record.isProvisional
        )
    }

    private static func gradient(for style: Int) -> [Color] {
        let gradients: [[Color]] = [
            [RezplyColor.peach, RezplyColor.primaryContainer],
            [RezplyColor.deepNavy, RezplyColor.surfaceDim],
            [RezplyColor.surfaceVariant, RezplyColor.secondaryContainer],
            [RezplyColor.secondaryContainer, RezplyColor.peach],
            [RezplyColor.surfaceVariant, RezplyColor.primaryFixed],
            [RezplyColor.primaryContainer, RezplyColor.deepNavy],
            [RezplyColor.surfaceContainerHigh, RezplyColor.secondaryContainer]
        ]
        return gradients[abs(style) % gradients.count]
    }
}

extension ChatMessage {
    init(record: ChatMessageRecord) {
        let sender: Sender
        switch record.senderKind {
        case "user":
            sender = .user
        case "other":
            sender = .other(record.senderName ?? "Participant")
        case "unknown":
            sender = .unknown
        default:
            sender = .contact
        }

        self.init(id: record.id, sender: sender, text: record.text, timeLabel: record.timeLabel)
    }
}

extension ContactContextRecord {
    func value(contactMemories: [ContactMemory] = []) -> ContactContext {
        return ContactContext(
            contactMemories: contactMemories,
            currentInteractionGoal: currentInteractionGoal,
            personaID: personaID,
            personaAssignedAt: personaAssignedAt
        )
    }

    func update(from value: ContactContext) {
        currentInteractionGoal = value.currentInteractionGoal
        personaID = value.personaID
        personaAssignedAt = value.personaAssignedAt
    }
}

extension PersonaRecord {
    var value: Persona {
        Persona(
            id: id, name: name, summary: summary, symbolName: symbolName,
            accentKey: accentKey, instructions: instructions,
            learningEnabled: learningEnabled,
            sampleCount: sampleCount, lastLearnedAt: lastLearnedAt
        )
    }
}

extension PersonaObservationRecord {
    var value: PersonaObservation {
        let ids =
            sourceMessageIDsJSON.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        return PersonaObservation(
            id: id,
            text: text,
            origin: PersonaObservationOrigin(rawValue: origin) ?? .ai,
            isUserProtected: isUserProtected,
            status: PersonaObservationStatus(rawValue: status) ?? .active,
            evidenceSource: PersonaObservationEvidenceSource(rawValue: evidenceSource) ?? .messages,
            sourceMessageIDs: ids,
            evidenceCount: evidenceCount,
            supersededByID: supersededByID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    convenience init(personaID: UUID, value: PersonaObservation) {
        let data = try? JSONEncoder().encode(value.sourceMessageIDs)
        self.init(
            id: value.id, personaID: personaID, text: value.text,
            origin: value.origin.rawValue, isUserProtected: value.isUserProtected,
            status: value.status.rawValue, evidenceSource: value.evidenceSource.rawValue,
            sourceMessageIDsJSON: data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
            evidenceCount: value.evidenceCount, supersededByID: value.supersededByID,
            createdAt: value.createdAt, updatedAt: value.updatedAt
        )
    }
}

extension ContactMemoryRecord {
    var value: ContactMemory {
        let sourceMessageIDs: [UUID]
        if let data = sourceMessageIDsJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([UUID].self, from: data)
        {
            sourceMessageIDs = decoded
        } else {
            sourceMessageIDs = []
        }

        return ContactMemory(
            id: id,
            text: text,
            origin: ContactMemoryOrigin(rawValue: origin) ?? .user,
            certainty: ContactMemoryCertainty(rawValue: certainty) ?? .userConfirmed,
            sourceMessageIDs: sourceMessageIDs,
            status: ContactMemoryStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    convenience init(chatID: String, value: ContactMemory) {
        let sourceData = try? JSONEncoder().encode(value.sourceMessageIDs)
        self.init(
            id: value.id,
            chatID: chatID,
            text: value.text,
            origin: value.origin.rawValue,
            certainty: value.certainty.rawValue,
            sourceMessageIDsJSON: sourceData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
            status: value.status.rawValue,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    func update(from value: ContactMemory) {
        text = value.text
        origin = value.origin.rawValue
        certainty = value.certainty.rawValue
        sourceMessageIDsJSON =
            (try? String(
                data: JSONEncoder().encode(value.sourceMessageIDs),
                encoding: .utf8
            )) ?? "[]"
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
