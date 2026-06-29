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
            timeLabel: record.lastActivityLabel,
            preview: record.preview,
            chipTitle: record.chipTitle,
            chipSymbol: record.chipSymbol,
            avatarSymbol: record.avatarSymbol,
            avatarData: record.avatarData,
            initials: record.initials,
            gradient: Self.gradient(for: record.appearanceStyle),
            isUnread: record.isUnread,
            isOnline: record.isOnline,
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
    var value: ContactContext {
        let facts: [String]
        if let data = keyFactsJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            facts = decoded
        } else {
            facts = []
        }

        return ContactContext(
            relationshipSubtitle: relationshipSubtitle,
            relationshipNotes: relationshipNotes,
            keyFacts: facts,
            currentInteractionGoal: currentInteractionGoal,
            preferredPersona: preferredPersona
        )
    }

    func update(from value: ContactContext) {
        relationshipSubtitle = value.relationshipSubtitle
        relationshipNotes = value.relationshipNotes
        keyFactsJSON = (try? String(data: JSONEncoder().encode(value.keyFacts), encoding: .utf8)) ?? "[]"
        currentInteractionGoal = value.currentInteractionGoal
        preferredPersona = value.preferredPersona
    }
}
