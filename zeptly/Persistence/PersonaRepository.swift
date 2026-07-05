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
        descriptor.sortBy = [SortDescriptor(\.category)]
        let records = try context.fetch(descriptor)
        return includeDismissed ? records : records.filter { $0.status == PersonaTraitStatus.active.rawValue }
    }

    func promptContext(personaID: UUID) throws -> PersonaPromptContext {
        let record = try persona(id: personaID)
            ?? persona(id: PersonaDefaults.professionalID)
            ?? Self.makeBuiltIn(.professional)
        return PersonaPromptContext(
            id: record.id,
            name: record.name,
            baseInstructions: record.baseInstructions,
            formality: PersonaFormality(rawValue: record.formality) ?? .balanced,
            warmth: PersonaWarmth(rawValue: record.warmth) ?? .balanced,
            length: PersonaLength(rawValue: record.replyLength) ?? .balanced,
            emojiUse: PersonaEmojiUse(rawValue: record.emojiUse) ?? .light,
            additionalGuidance: record.additionalGuidance,
            learnedTraits: try traits(personaID: record.id).map(\.value)
        )
    }

    func create(name: String, template: PersonaTemplate) throws -> PersonaRecord {
        let base = Self.makeBuiltIn(template)
        let record = PersonaRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: "A custom voice based on \(template.displayName.lowercased()).",
            symbolName: base.symbolName, accentKey: base.accentKey,
            templateKey: template.rawValue, isBuiltIn: false,
            baseInstructions: base.baseInstructions, formality: base.formality,
            warmth: base.warmth, replyLength: base.replyLength, emojiUse: base.emojiUse
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
            baseInstructions: source.baseInstructions, formality: source.formality,
            warmth: source.warmth, replyLength: source.replyLength,
            emojiUse: source.emojiUse, additionalGuidance: source.additionalGuidance
        )
        context.insert(record)
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
        for receipt in try context.fetch(FetchDescriptor<PersonaLearningReceiptRecord>(predicate: #Predicate { $0.personaID == deletedID })) {
            context.delete(receipt)
        }
        context.delete(record)
        try context.save()
    }

    static func makeBuiltIn(_ template: PersonaTemplate) -> PersonaRecord {
        switch template {
        case .professional:
            PersonaRecord(
                id: PersonaDefaults.professionalID, name: template.displayName,
                summary: "Concise, polished replies for work and formal conversations.",
                symbolName: "briefcase", accentKey: "primary", templateKey: template.rawValue,
                isBuiltIn: true,
                baseInstructions: "Write polished, clear, structured messages. Be decisive and avoid filler.",
                formality: PersonaFormality.formal.rawValue, warmth: PersonaWarmth.balanced.rawValue,
                replyLength: PersonaLength.short.rawValue, emojiUse: PersonaEmojiUse.none.rawValue
            )
        case .spark:
            PersonaRecord(
                id: PersonaDefaults.sparkID, name: template.displayName,
                summary: "Playful, confident, genuine dating messages that read the room.",
                symbolName: "sparkles", accentKey: "peach", templateKey: template.rawValue,
                isBuiltIn: true,
                baseInstructions: "Write playful, confident, genuine dating messages. Match the other person's emotional intensity and never force flirtation or over-escalate.",
                formality: PersonaFormality.casual.rawValue, warmth: PersonaWarmth.warm.rawValue,
                replyLength: PersonaLength.short.rawValue, emojiUse: PersonaEmojiUse.light.rawValue
            )
        case .thoughtful:
            PersonaRecord(
                id: PersonaDefaults.thoughtfulID, name: template.displayName,
                summary: "Warm, empathetic replies for friends, family, and delicate moments.",
                symbolName: "heart.text.square", accentKey: "secondary", templateKey: template.rawValue,
                isBuiltIn: true,
                baseInstructions: "Write warm, empathetic, tactful messages. Acknowledge emotion without inventing feelings or becoming overly sentimental.",
                formality: PersonaFormality.balanced.rawValue, warmth: PersonaWarmth.warm.rawValue,
                replyLength: PersonaLength.balanced.rawValue, emojiUse: PersonaEmojiUse.light.rawValue
            )
        }
    }
}
