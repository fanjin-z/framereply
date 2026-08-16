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

nonisolated enum ChatMemoryLimits {
    static let maximumAITextCodePoints = 120
}

nonisolated enum PersonalInfoFactOrigin: String, Codable, Equatable, Sendable {
    case user
    case ai
}

nonisolated enum PersonalInfoLimits {
    static let maximumActiveFacts = 50
    static let maximumTextCodePoints = 120
    static let maximumChangesPerGeneration = 8
}

nonisolated struct PersonalInfoFact: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var origin: PersonalInfoFactOrigin

    var isUserProtected: Bool {
        origin == .user
    }

    init(
        id: UUID = UUID(),
        text: String,
        origin: PersonalInfoFactOrigin = .user
    ) {
        self.id = id
        self.text = text
        self.origin = origin
    }
}

nonisolated struct PersonalInfoPromptContext: Codable, Equatable, Sendable {
    var facts: [PersonalInfoFact]

    static let empty = PersonalInfoPromptContext(facts: [])
}

nonisolated enum PersonalInfoReconciler {
    static func reconcile(
        facts: [PersonalInfoFact],
        changes: [PersonalInfoChange],
        allowedUserSourceMessageIDs: Set<UUID>
    ) -> [PersonalInfoFact] {
        var result = facts

        for change in changes.prefix(PersonalInfoLimits.maximumChangesPerGeneration) {
            let evidence = change.sourceMessageIDs
            guard (1...3).contains(evidence.count),
                Set(evidence).count == evidence.count,
                evidence.allSatisfy(allowedUserSourceMessageIDs.contains)
            else { continue }

            switch change.action {
            case .add:
                guard change.targetFactID == nil,
                    result.count < PersonalInfoLimits.maximumActiveFacts,
                    let text = cleaned(change.text),
                    !containsEquivalent(text, in: result)
                else { continue }
                result.append(
                    PersonalInfoFact(
                        text: text,
                        origin: .ai
                    )
                )

            case .update:
                guard let targetID = change.targetFactID,
                    let index = result.firstIndex(where: {
                        $0.id == targetID && !$0.isUserProtected
                    }),
                    let text = cleaned(change.text),
                    !containsEquivalent(text, in: result, excluding: targetID)
                else { continue }
                result[index].text = text
                result[index].origin = .ai

            case .archive:
                guard let targetID = change.targetFactID,
                    let index = result.firstIndex(where: {
                        $0.id == targetID && !$0.isUserProtected
                    })
                else { continue }
                result.remove(at: index)
            }
        }

        return result
    }

    static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty
            || value.unicodeScalars.count > PersonalInfoLimits.maximumTextCodePoints
            ? nil : value
    }

    static func comparisonKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
    }

    private static func containsEquivalent(
        _ text: String,
        in facts: [PersonalInfoFact],
        excluding excludedID: UUID? = nil
    ) -> Bool {
        let key = comparisonKey(text)
        return facts.contains {
            $0.id != excludedID
                && comparisonKey($0.text) == key
        }
    }
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
        eligibleSourceMessageIDs: Set<UUID>,
        now: Date = Date()
    ) -> [ChatMemory] {
        var result = memories

        for change in changes {
            let evidence = change.sourceMessageIDs
            guard !evidence.isEmpty,
                Set(evidence).count == evidence.count,
                evidence.allSatisfy(eligibleSourceMessageIDs.contains)
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
        return value.isEmpty
            || value.unicodeScalars.count > ChatMemoryLimits.maximumAITextCodePoints
            ? nil : value
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
