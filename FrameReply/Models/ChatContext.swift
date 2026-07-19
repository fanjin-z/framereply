//
//  ChatContext.swift
//  FrameReply
//

import Foundation

nonisolated struct ChatParticipantAlias: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayLabel: String

    init(
        id: UUID = UUID(),
        displayLabel: String
    ) {
        self.id = id
        self.displayLabel = displayLabel
    }

    var normalizedLabel: String {
        Self.normalizedKey(displayLabel) ?? ""
    }

    static func displayLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed =
            value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func normalizedKey(_ value: String?) -> String? {
        guard let displayLabel = displayLabel(value) else { return nil }
        return displayLabel
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

nonisolated enum ChatMemoryOrigin: String, Codable, Equatable, Sendable {
    case user
    case ai
}

nonisolated enum ChatMemoryCertainty: String, Codable, Equatable, Sendable {
    case userConfirmed
    case aiInferred
}

nonisolated enum ChatMemoryStatus: String, Codable, Equatable, Sendable {
    case active
    case archived
    case superseded
}

nonisolated struct ChatMemory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var origin: ChatMemoryOrigin
    var certainty: ChatMemoryCertainty
    var status: ChatMemoryStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        origin: ChatMemoryOrigin = .user,
        certainty: ChatMemoryCertainty = .userConfirmed,
        status: ChatMemoryStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.origin = origin
        self.certainty = certainty
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatContext: Equatable {
    var chatMemories: [ChatMemory]
    var currentInteractionGoal: String
    var personaID: UUID
    var personaAssignedAt: Date
    var participantAliases: [ChatParticipantAlias] = []

    static func empty(personaID: UUID) -> ChatContext {
        ChatContext(
            chatMemories: [],
            currentInteractionGoal: "",
            personaID: personaID,
            personaAssignedAt: Date(),
            participantAliases: []
        )
    }
}

nonisolated enum ChatMemoryReconciler {
    static func reconcile(
        memories: [ChatMemory],
        changes: [ChatMemoryChange],
        allowedOtherParticipantSourceMessageIDs: Set<UUID>,
        now: Date = Date()
    ) -> [ChatMemory] {
        var result = memories

        for change in changes {
            let evidence = change.sourceMessageIDs
            guard !evidence.isEmpty,
                Set(evidence).count == evidence.count,
                evidence.allSatisfy(allowedOtherParticipantSourceMessageIDs.contains)
            else {
                continue
            }

            switch change.action {
            case .add:
                guard change.targetMemoryID == nil,
                    let text = cleaned(change.text),
                    activeEquivalent(to: text, in: result, excluding: nil) == nil
                else {
                    continue
                }
                result.append(
                    ChatMemory(
                        text: text,
                        origin: .ai,
                        certainty: .aiInferred,
                        status: .active,
                        createdAt: now,
                        updatedAt: now
                    )
                )

            case .update:
                guard let targetID = change.targetMemoryID,
                    let targetIndex = result.firstIndex(where: {
                        $0.id == targetID && $0.status == .active
                    }),
                    let text = cleaned(change.text)
                else {
                    continue
                }

                if let duplicateIndex = activeEquivalent(
                    to: text,
                    in: result,
                    excluding: targetID
                ) {
                    result[targetIndex].status = .superseded
                    result[targetIndex].updatedAt = now
                    result[duplicateIndex].updatedAt = now
                } else if result[targetIndex].origin == .ai {
                    result[targetIndex].text = text
                    result[targetIndex].certainty = .aiInferred
                    result[targetIndex].updatedAt = now
                } else {
                    result[targetIndex].status = .superseded
                    result[targetIndex].updatedAt = now
                    result.append(
                        ChatMemory(
                            text: text,
                            origin: .ai,
                            certainty: .aiInferred,
                            status: .active,
                            createdAt: now,
                            updatedAt: now
                        )
                    )
                }

            case .archive:
                guard let targetID = change.targetMemoryID,
                    let targetIndex = result.firstIndex(where: {
                        $0.id == targetID && $0.status == .active
                    })
                else {
                    continue
                }
                result[targetIndex].status = .archived
                result[targetIndex].updatedAt = now
            }
        }

        return result
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.count > 240 ? nil : value
    }

    private static func activeEquivalent(
        to text: String,
        in memories: [ChatMemory],
        excluding excludedID: UUID?
    ) -> Int? {
        let key = comparisonKey(text)
        return memories.firstIndex {
            $0.id != excludedID
                && $0.status == .active
                && comparisonKey($0.text) == key
        }
    }

    private static func comparisonKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
    }

}
