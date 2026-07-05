//
//  ContactContext.swift
//  zeptly
//

import Foundation

nonisolated enum ContactMemoryKind: String, Codable, CaseIterable, Equatable, Sendable {
    case relationship
    case preference
    case person
    case event
    case fact
    case other
}

nonisolated enum ContactMemoryOrigin: String, Codable, Equatable, Sendable {
    case user
    case ai
}

nonisolated enum ContactMemoryCertainty: String, Codable, Equatable, Sendable {
    case userConfirmed
    case aiInferred
}

nonisolated enum ContactMemoryStatus: String, Codable, Equatable, Sendable {
    case active
    case archived
    case superseded
}

nonisolated struct ContactMemory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var kind: ContactMemoryKind
    var origin: ContactMemoryOrigin
    var certainty: ContactMemoryCertainty
    var sourceMessageIDs: [UUID]
    var status: ContactMemoryStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        kind: ContactMemoryKind = .other,
        origin: ContactMemoryOrigin = .user,
        certainty: ContactMemoryCertainty = .userConfirmed,
        sourceMessageIDs: [UUID] = [],
        status: ContactMemoryStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.origin = origin
        self.certainty = certainty
        self.sourceMessageIDs = sourceMessageIDs
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ContactContext: Equatable {
    var relationshipSubtitle: String
    var contactMemories: [ContactMemory]
    var currentInteractionGoal: String
    var personaID: UUID
    var personaAssignedAt: Date

    static let empty = ContactContext(
        relationshipSubtitle: "",
        contactMemories: [],
        currentInteractionGoal: "",
        personaID: PersonaDefaults.professionalID,
        personaAssignedAt: Date()
    )
}

nonisolated enum ContactMemoryReconciler {
    static func reconcile(
        memories: [ContactMemory],
        changes: [ContactMemoryChange],
        allowedContactSourceMessageIDs: Set<UUID>,
        now: Date = Date()
    ) -> [ContactMemory] {
        var result = memories

        for change in changes {
            let evidence = change.sourceMessageIDs
            guard !evidence.isEmpty,
                Set(evidence).count == evidence.count,
                evidence.allSatisfy(allowedContactSourceMessageIDs.contains)
            else {
                continue
            }

            switch change.action {
            case .add:
                guard change.targetMemoryID == nil,
                    let text = cleaned(change.text),
                    let kind = change.kind,
                    activeEquivalent(to: text, kind: kind, in: result, excluding: nil) == nil
                else {
                    continue
                }
                result.append(
                    ContactMemory(
                        text: text,
                        kind: kind,
                        origin: .ai,
                        certainty: .aiInferred,
                        sourceMessageIDs: evidence,
                        status: .active,
                        createdAt: now,
                        updatedAt: now
                    )
                )

            case .update:
                guard let targetID = change.targetMemoryID,
                    let targetIndex = result.firstIndex(where: { $0.id == targetID && $0.status == .active }),
                    let text = cleaned(change.text),
                    let kind = change.kind
                else {
                    continue
                }

                if let duplicateIndex = activeEquivalent(
                    to: text,
                    kind: kind,
                    in: result,
                    excluding: targetID
                ) {
                    result[targetIndex].status = .superseded
                    result[targetIndex].sourceMessageIDs = merged(
                        result[targetIndex].sourceMessageIDs,
                        evidence
                    )
                    result[targetIndex].updatedAt = now
                    result[duplicateIndex].sourceMessageIDs = merged(
                        result[duplicateIndex].sourceMessageIDs,
                        evidence
                    )
                    result[duplicateIndex].updatedAt = now
                } else if result[targetIndex].origin == .ai {
                    result[targetIndex].text = text
                    result[targetIndex].kind = kind
                    result[targetIndex].certainty = .aiInferred
                    result[targetIndex].sourceMessageIDs = merged(
                        result[targetIndex].sourceMessageIDs,
                        evidence
                    )
                    result[targetIndex].updatedAt = now
                } else {
                    result[targetIndex].status = .superseded
                    result[targetIndex].sourceMessageIDs = merged(
                        result[targetIndex].sourceMessageIDs,
                        evidence
                    )
                    result[targetIndex].updatedAt = now
                    result.append(
                        ContactMemory(
                            text: text,
                            kind: kind,
                            origin: .ai,
                            certainty: .aiInferred,
                            sourceMessageIDs: evidence,
                            status: .active,
                            createdAt: now,
                            updatedAt: now
                        )
                    )
                }

            case .archive:
                guard let targetID = change.targetMemoryID,
                    let targetIndex = result.firstIndex(where: { $0.id == targetID && $0.status == .active })
                else {
                    continue
                }
                result[targetIndex].status = .archived
                result[targetIndex].sourceMessageIDs = merged(
                    result[targetIndex].sourceMessageIDs,
                    evidence
                )
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
        kind: ContactMemoryKind,
        in memories: [ContactMemory],
        excluding excludedID: UUID?
    ) -> Int? {
        let key = comparisonKey(text)
        return memories.firstIndex {
            $0.id != excludedID
                && $0.status == .active
                && $0.kind == kind
                && comparisonKey($0.text) == key
        }
    }

    private static func comparisonKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
    }

    private static func merged(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return (lhs + rhs).filter { seen.insert($0).inserted }
    }
}
