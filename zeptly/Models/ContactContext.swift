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
    var preferredPersona: String

    static let empty = ContactContext(
        relationshipSubtitle: "",
        contactMemories: [],
        currentInteractionGoal: "",
        preferredPersona: "Professional"
    )
}
