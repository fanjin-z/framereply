import Foundation
import SwiftData

@MainActor
final class PersonaRepository {
    private let context: ModelContext

    convenience init() { self.init(container: ZeptlyDataStore.shared) }
    init(container: ModelContainer) { context = container.mainContext }

    nonisolated deinit {}

    func seedBuiltInsIfNeeded() throws {
        for template in PersonaTemplate.allCases where try persona(id: PersonaDefaults.id(for: template)) == nil {
            context.insert(Self.makeBuiltIn(template))
        }
        try context.save()
    }

    func personas() throws -> [PersonaRecord] {
        var descriptor = FetchDescriptor<PersonaRecord>()
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    func persona(id: UUID) throws -> PersonaRecord? {
        try context.fetch(FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func traits(personaID: UUID, includeDismissed: Bool = false) throws -> [PersonaLearnedTraitRecord] {
        var descriptor = FetchDescriptor<PersonaLearnedTraitRecord>(
            predicate: #Predicate { $0.personaID == personaID }
        )
        descriptor.sortBy = [SortDescriptor(\.dimensionKey)]
        let records = try context.fetch(descriptor)
        return includeDismissed ? records : records.filter { $0.status == PersonaTraitStatus.active.rawValue }
    }

    func adjustments(personaID: UUID) throws -> [PersonaStyleAdjustmentRecord] {
        try context.fetch(FetchDescriptor<PersonaStyleAdjustmentRecord>(predicate: #Predicate { $0.personaID == personaID }))
    }

    func promptContext(personaID: UUID) throws -> PersonaPromptContext {
        let record = try persona(id: personaID)
            ?? persona(id: PersonaDefaults.professionalID)
            ?? Self.makeBuiltIn(.professional)
        return try Self.promptContext(
            record: record,
            traits: traits(personaID: record.id),
            adjustments: adjustments(personaID: record.id)
        )
    }

    func create(name: String, template: PersonaTemplate) throws -> PersonaRecord {
        let base = Self.makeBuiltIn(template)
        let record = PersonaRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: "A custom voice based on \(template.displayName.lowercased()).",
            symbolName: base.symbolName, accentKey: base.accentKey,
            templateKey: template.rawValue, isBuiltIn: false,
            purposeInstructions: base.purposeInstructions,
            baselineStyleJSON: base.baselineStyleJSON
        )
        context.insert(record)
        try context.save()
        return record
    }

    func duplicate(_ source: PersonaRecord) throws -> PersonaRecord {
        let record = PersonaRecord(
            name: "\(source.name) Copy", summary: source.summary,
            symbolName: source.symbolName, accentKey: source.accentKey,
            templateKey: source.templateKey, isBuiltIn: false,
            purposeInstructions: source.purposeInstructions,
            baselineStyleJSON: source.baselineStyleJSON,
            alwaysFollowRules: source.alwaysFollowRules
        )
        context.insert(record)
        for adjustment in try adjustments(personaID: source.id) {
            context.insert(PersonaStyleAdjustmentRecord(
                personaID: record.id,
                dimensionKey: adjustment.dimensionKey,
                adjustment: adjustment.adjustment
            ))
        }
        try context.save()
        return record
    }

    func usageCount(personaID: UUID) throws -> Int {
        try context.fetchCount(FetchDescriptor<ContactContextRecord>(predicate: #Predicate { $0.personaID == personaID }))
    }

    func assign(personaID: UUID, to contextRecord: ContactContextRecord, at date: Date = Date()) throws {
        guard contextRecord.personaID != personaID else { return }
        contextRecord.personaID = personaID
        contextRecord.personaAssignedAt = date
        try context.save()
    }

    func setAdjustment(_ adjustment: Int, dimensionKey: String, personaID: UUID) throws {
        guard let definition = PersonaStyleDimensionRegistry.definition(for: dimensionKey),
            definition.userAdjustable
        else { return }
        let key = "\(personaID.uuidString.lowercased())|\(dimensionKey)"
        let existing = try context.fetch(
            FetchDescriptor<PersonaStyleAdjustmentRecord>(predicate: #Predicate { $0.key == key })
        ).first
        let clamped = min(2, max(-2, adjustment))
        if clamped == 0 {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.adjustment = clamped
            existing.updatedAt = Date()
        } else {
            context.insert(PersonaStyleAdjustmentRecord(
                personaID: personaID, dimensionKey: dimensionKey, adjustment: clamped
            ))
        }
        if let persona = try persona(id: personaID) { persona.updatedAt = Date() }
        try context.save()
    }

    func setLearningEnabled(_ enabled: Bool, for record: PersonaRecord, at date: Date = Date()) throws {
        record.learningEnabled = enabled
        if enabled { record.learningEnabledAt = date }
        record.updatedAt = date
        try context.save()
    }

    func resetLearnedStyle(personaID: UUID) throws {
        for trait in try traits(personaID: personaID, includeDismissed: true) { context.delete(trait) }
        if let persona = try persona(id: personaID) {
            persona.sampleCount = 0
            persona.lastLearnedAt = nil
            persona.updatedAt = Date()
        }
        try context.save()
    }

    func delete(_ record: PersonaRecord) throws {
        guard !record.isBuiltIn else { return }
        let deletedID = record.id
        for contact in try context.fetch(FetchDescriptor<ContactContextRecord>(predicate: #Predicate { $0.personaID == deletedID })) {
            contact.personaID = PersonaDefaults.professionalID
            contact.personaAssignedAt = Date()
        }
        for trait in try traits(personaID: deletedID, includeDismissed: true) { context.delete(trait) }
        for adjustment in try adjustments(personaID: deletedID) { context.delete(adjustment) }
        for receipt in try context.fetch(FetchDescriptor<PersonaLearningReceiptRecord>(predicate: #Predicate { $0.personaID == deletedID })) {
            context.delete(receipt)
        }
        context.delete(record)
        try context.save()
    }

    static func promptContext(
        record: PersonaRecord,
        traits: [PersonaLearnedTraitRecord],
        adjustments: [PersonaStyleAdjustmentRecord]
    ) -> PersonaPromptContext {
        let traitValues = traits.map(\.value)
        let adjustmentValues = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.dimensionKey, $0.adjustment) })
        let resolved = PersonaStyleResolver.resolve(
            baseline: record.baselineStyle,
            adjustments: adjustmentValues,
            traits: traitValues
        )
        let descriptive = traitValues.filter { trait in
            guard let definition = PersonaStyleDimensionRegistry.definition(for: trait.dimensionKey) else { return false }
            return definition.observationOnly || trait.origin == .userConfirmed
        }
        return PersonaPromptContext(
            id: record.id,
            name: record.name,
            purposeInstructions: record.purposeInstructions,
            resolvedStyle: resolved,
            descriptiveObservations: descriptive,
            alwaysFollowRules: record.alwaysFollowRules,
            registryVersion: PersonaStyleDimensionRegistry.version,
            resolverVersion: PersonaStyleResolver.version
        )
    }

    static func makeBuiltIn(_ template: PersonaTemplate) -> PersonaRecord {
        let common = (
            baselineStyleJSON: encodeBaseline(PersonaStyleDimensionRegistry.presetBaseline(for: template)),
            id: PersonaDefaults.id(for: template)
        )
        switch template {
        case .professional:
            return PersonaRecord(
                id: common.id, name: template.displayName,
                summary: "Concise, polished replies for work and formal conversations.",
                symbolName: "briefcase", accentKey: "primary", templateKey: template.rawValue,
                isBuiltIn: true,
                purposeInstructions: "Write clear, structured messages for professional and formal conversations. Be decisive and avoid filler.",
                baselineStyleJSON: common.baselineStyleJSON
            )
        case .spark:
            return PersonaRecord(
                id: common.id, name: template.displayName,
                summary: "Playful, confident, genuine dating messages that read the room.",
                symbolName: "sparkles", accentKey: "peach", templateKey: template.rawValue,
                isBuiltIn: true,
                purposeInstructions: "Write genuine dating messages that read the room. Match the other person's emotional intensity and never force flirtation or over-escalate.",
                baselineStyleJSON: common.baselineStyleJSON
            )
        case .thoughtful:
            return PersonaRecord(
                id: common.id, name: template.displayName,
                summary: "Warm, empathetic replies for friends, family, and delicate moments.",
                symbolName: "heart.text.square", accentKey: "secondary", templateKey: template.rawValue,
                isBuiltIn: true,
                purposeInstructions: "Write tactful messages for friends, family, and delicate moments. Acknowledge emotion without inventing feelings or becoming overly sentimental.",
                baselineStyleJSON: common.baselineStyleJSON
            )
        }
    }

    private static func encodeBaseline(_ baseline: [String: Double]) -> String {
        guard let data = try? JSONEncoder().encode(baseline) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
