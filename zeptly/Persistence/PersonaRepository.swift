import Foundation
import SwiftData

nonisolated enum PersonaRepositoryError: Error, Equatable {
    case noPersonas
    case cannotDeleteLastPersona
    case replacementDefaultRequired
    case invalidDefaultPersona
    case observationLimitReached
}

@MainActor
final class PersonaRepository {
    private static let seededKey = "personasSeeded"
    private static let defaultPersonaKey = "defaultPersonaID"
    private let context: ModelContext

    convenience init() { self.init(container: ZeptlyDataStore.shared) }
    init(container: ModelContainer) { context = container.mainContext }
    init(context: ModelContext) { self.context = context }

    nonisolated deinit {}

    func seedPersonasIfNeeded() throws {
        guard try metadata(Self.seededKey) == nil else { return }
        var initialDefaultID: UUID?
        for seed in Self.seeds {
            let personaID = UUID()
            initialDefaultID = initialDefaultID ?? personaID
            let record = PersonaRecord(
                id: personaID, name: seed.name, summary: seed.summary,
                symbolName: seed.symbolName, accentKey: seed.accentKey,
                instructions: seed.instructions
            )
            context.insert(record)
            for text in seed.observations {
                context.insert(
                    observationRecord(
                        personaID: personaID, text: text, origin: .seed,
                        isUserProtected: false
                    ))
            }
        }
        guard let initialDefaultID else { throw PersonaRepositoryError.noPersonas }
        context.insert(StoreMetadataRecord(key: Self.seededKey, value: "1"))
        context.insert(
            StoreMetadataRecord(
                key: Self.defaultPersonaKey, value: initialDefaultID.uuidString.lowercased()
            ))
        try context.save()
    }

    func personas() throws -> [PersonaRecord] {
        var descriptor = FetchDescriptor<PersonaRecord>()
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    func persona(id: UUID) throws -> PersonaRecord? {
        try context.fetch(FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.id == id }))
            .first
    }

    func observations(personaID: UUID, includeInactive: Bool = false) throws
        -> [PersonaObservationRecord]
    {
        var descriptor = FetchDescriptor<PersonaObservationRecord>(
            predicate: #Predicate { $0.personaID == personaID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
        let records = try context.fetch(descriptor)
        return includeInactive
            ? records : records.filter { $0.status == PersonaObservationStatus.active.rawValue }
    }

    func defaultPersonaID() throws -> UUID {
        try defaultPersona().id
    }

    func defaultPersona() throws -> PersonaRecord {
        guard try !personas().isEmpty else { throw PersonaRepositoryError.noPersonas }
        guard let value = try metadata(Self.defaultPersonaKey)?.value,
            let id = UUID(uuidString: value), let record = try persona(id: id)
        else {
            throw PersonaRepositoryError.invalidDefaultPersona
        }
        return record
    }

    func setDefaultPersona(id: UUID) throws {
        try updateDefaultPersona(id: id)
        try context.save()
    }

    private func updateDefaultPersona(id: UUID) throws {
        guard try persona(id: id) != nil else { throw PersonaRepositoryError.invalidDefaultPersona }
        if let record = try metadata(Self.defaultPersonaKey) {
            record.value = id.uuidString.lowercased()
        } else {
            context.insert(
                StoreMetadataRecord(key: Self.defaultPersonaKey, value: id.uuidString.lowercased()))
        }
    }

    func promptContext(personaID: UUID) throws -> PersonaPromptContext {
        let record = try persona(id: personaID) ?? defaultPersona()
        return Self.promptContext(
            record: record,
            observations: try observations(personaID: record.id, includeInactive: true)
        )
    }

    func create(
        name: String,
        summary: String,
        instructions: String,
        observations: [PersonaObservation],
        symbolName: String = "person.crop.circle",
        accentKey: String = "primary"
    ) throws -> PersonaRecord {
        let record = PersonaRecord(
            name: cleaned(name), summary: cleaned(summary), symbolName: symbolName,
            accentKey: accentKey, instructions: cleaned(instructions)
        )
        context.insert(record)
        for observation in uniqueActive(observations).prefix(
            PersonaLimits.maximumActiveObservations)
        {
            context.insert(PersonaObservationRecord(personaID: record.id, value: observation))
        }
        try context.save()
        return record
    }

    func duplicate(_ source: PersonaRecord) throws -> PersonaRecord {
        let copied = try observations(personaID: source.id).map {
            Self.makeObservation(
                text: $0.text, origin: .seed, isUserProtected: false
            )
        }
        return try create(
            name: "\(source.name) Copy", summary: source.summary,
            instructions: source.instructions, observations: copied,
            symbolName: source.symbolName, accentKey: source.accentKey
        )
    }

    func addUserObservation(_ text: String, personaID: UUID) throws {
        guard try observations(personaID: personaID).count < PersonaLimits.maximumActiveObservations
        else {
            throw PersonaRepositoryError.observationLimitReached
        }
        let value = cleaned(text)
        guard !value.isEmpty, try !containsActive(text: value, personaID: personaID) else { return }
        context.insert(
            observationRecord(
                personaID: personaID, text: value, origin: .user,
                isUserProtected: true
            ))
        try touch(personaID: personaID)
        try context.save()
    }

    func updateObservation(_ record: PersonaObservationRecord, text: String) throws {
        let value = cleaned(text)
        guard !value.isEmpty else { return }
        record.text = value
        record.origin = PersonaObservationOrigin.user.rawValue
        record.isUserProtected = true
        record.updatedAt = Date()
        try touch(personaID: record.personaID)
        try context.save()
    }

    func archiveObservation(_ record: PersonaObservationRecord) throws {
        record.status = PersonaObservationStatus.archived.rawValue
        record.isUserProtected = true
        record.updatedAt = Date()
        try touch(personaID: record.personaID)
        try context.save()
    }

    func clearLearnedObservations(personaID: UUID) throws {
        for record in try observations(personaID: personaID)
        where record.origin == PersonaObservationOrigin.ai.rawValue && !record.isUserProtected {
            record.status = PersonaObservationStatus.archived.rawValue
            record.updatedAt = Date()
        }
        if let persona = try persona(id: personaID) {
            persona.sampleCount = 0
            persona.updatedAt = Date()
        }
        try context.save()
    }

    func usageCount(personaID: UUID) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<ChatContextRecord>(
                predicate: #Predicate { $0.personaID == personaID }))
    }

    func setLearningEnabled(_ enabled: Bool, for record: PersonaRecord, at date: Date = Date())
        throws
    {
        record.learningEnabled = enabled
        if enabled { record.learningEnabledAt = date }
        record.updatedAt = date
        try context.save()
    }

    func delete(_ record: PersonaRecord, replacementDefaultID: UUID? = nil) throws {
        guard try personas().count > 1 else { throw PersonaRepositoryError.cannotDeleteLastPersona }
        let currentDefault = try defaultPersonaID()
        let fallbackID: UUID
        if record.id == currentDefault {
            guard let replacementDefaultID else {
                throw PersonaRepositoryError.replacementDefaultRequired
            }
            guard replacementDefaultID != record.id, try persona(id: replacementDefaultID) != nil
            else {
                throw PersonaRepositoryError.invalidDefaultPersona
            }
            fallbackID = replacementDefaultID
            try updateDefaultPersona(id: fallbackID)
        } else {
            fallbackID = currentDefault
        }

        do {
            let deletedID = record.id
            for assignment in try context.fetch(
                FetchDescriptor<ChatContextRecord>(
                    predicate: #Predicate { $0.personaID == deletedID }))
            {
                assignment.personaID = fallbackID
                assignment.personaAssignedAt = Date()
            }
            for observation in try observations(personaID: deletedID, includeInactive: true) {
                context.delete(observation)
            }
            for receipt in try context.fetch(
                FetchDescriptor<PersonaLearningReceiptRecord>(
                    predicate: #Predicate { $0.personaID == deletedID }))
            {
                context.delete(receipt)
            }
            context.delete(record)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func promptContext(record: PersonaRecord, observations: [PersonaObservationRecord])
        -> PersonaPromptContext
    {
        let values = observations.map(\.value)
        let active =
            values
            .filter { $0.status == .active }
            .sorted {
                if $0.isUserProtected != $1.isUserProtected { return $0.isUserProtected }
                return $0.createdAt < $1.createdAt
            }
        return PersonaPromptContext(
            id: record.id, name: record.name,
            instructions: record.instructions, observations: active,
            protectedTombstones: values.filter {
                $0.status == .archived && $0.isUserProtected
            }
        )
    }

    static func makeObservation(
        text: String,
        origin: PersonaObservationOrigin,
        isUserProtected: Bool,
        now: Date = Date()
    ) -> PersonaObservation {
        PersonaObservation(
            id: UUID(), text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            origin: origin, isUserProtected: isUserProtected, status: .active,
            createdAt: now, updatedAt: now
        )
    }

    private func observationRecord(
        personaID: UUID, text: String, origin: PersonaObservationOrigin,
        isUserProtected: Bool
    ) -> PersonaObservationRecord {
        PersonaObservationRecord(
            personaID: personaID,
            value: Self.makeObservation(
                text: text, origin: origin, isUserProtected: isUserProtected
            ))
    }

    private func metadata(_ key: String) throws -> StoreMetadataRecord? {
        try context.fetch(
            FetchDescriptor<StoreMetadataRecord>(predicate: #Predicate { $0.key == key })
        ).first
    }

    private func containsActive(text: String, personaID: UUID) throws -> Bool {
        let normalized = cleaned(text).lowercased()
        return try observations(personaID: personaID).contains {
            cleaned($0.text).lowercased() == normalized
        }
    }

    private func uniqueActive(_ values: [PersonaObservation]) -> [PersonaObservation] {
        var seen = Set<String>()
        return values.filter {
            guard $0.status == .active else { return false }
            return seen.insert(cleaned($0.text).lowercased()).inserted
        }
    }

    private func touch(personaID: UUID) throws {
        try persona(id: personaID)?.updatedAt = Date()
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Seed {
        let name: String
        let summary: String
        let symbolName: String
        let accentKey: String
        let instructions: String
        let observations: [String]
    }

    private static let seeds: [Seed] = [
        .init(
            name: "Professional",
            summary: "Concise, polished replies for work and formal conversations.",
            symbolName: "briefcase", accentKey: "primary",
            instructions:
                "Write clear, structured messages for professional and formal conversations. Be decisive and avoid filler.",
            observations: [
                "Uses polished, complete phrasing while remaining conversational.",
                "Keeps replies concise and omits nonessential detail.",
                "States the main point clearly and directly.",
                "Does not use emoji."
            ]
        ),
        .init(
            name: "Spark",
            summary: "Playful, confident, genuine dating messages that read the room.",
            symbolName: "sparkles", accentKey: "peach",
            instructions:
                "Write genuine dating messages that read the room. Match the other person's emotional intensity and never force flirtation or over-escalate.",
            observations: [
                "Keeps wording casual and conversational.",
                "Shows clear warmth and considerate acknowledgment.",
                "Keeps replies concise and omits nonessential detail.",
                "Allows light playfulness when it fits naturally."
            ]
        ),
        .init(
            name: "Thoughtful",
            summary: "Warm, empathetic replies for friends, family, and delicate moments.",
            symbolName: "heart.text.square", accentKey: "secondary",
            instructions:
                "Write tactful messages for friends, family, and delicate moments. Acknowledge emotion without inventing feelings or becoming overly sentimental.",
            observations: [
                "Shows clear warmth and considerate acknowledgment.",
                "Balances clarity with tact.",
                "Uses the amount of detail naturally required by the message.",
                "Uses an occasional emoji only when it fits the conversation."
            ]
        )
    ]
}
