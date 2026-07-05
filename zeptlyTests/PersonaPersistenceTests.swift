import SwiftData
import XCTest

@testable import zeptly

@MainActor
final class PersonaPersistenceTests: XCTestCase {
    func testBuiltInSeedingIsIdempotent() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)

        try repository.seedBuiltInsIfNeeded()
        try repository.seedBuiltInsIfNeeded()

        XCTAssertEqual(try repository.personas().map(\.name), [
            "The Professional", "The Spark", "The Thoughtful"
        ])
        XCTAssertEqual(Set(try repository.personas().map(\.id)).count, 3)
    }

    func testDeletingCustomPersonaReassignsChatsToProfessional() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedBuiltInsIfNeeded()
        let custom = try repository.create(name: "Weekend Voice", template: .spark)
        let assignment = ContactContextRecord(
            chatID: "chat", relationshipSubtitle: "", currentInteractionGoal: "",
            personaID: custom.id
        )
        container.mainContext.insert(assignment)
        try container.mainContext.save()

        try repository.delete(custom)

        XCTAssertEqual(assignment.personaID, PersonaDefaults.professionalID)
        XCTAssertNil(try repository.persona(id: custom.id))
    }

    func testLearningUsesOnlyFutureUnprocessedUserMessages() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedBuiltInsIfNeeded()
        let assignedAt = Date()
        let old = message(chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(-1))
        let contact = message(chatID: "chat", sender: "contact", createdAt: assignedAt.addingTimeInterval(1))
        let future = message(chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(2))
        container.mainContext.insert(old)
        container.mainContext.insert(contact)
        container.mainContext.insert(future)
        try container.mainContext.save()

        XCTAssertEqual(
            try chats.personaLearningMessages(
                chatID: "chat", personaID: PersonaDefaults.professionalID, assignedAt: assignedAt
            ).map(\.id),
            [future.id]
        )

        container.mainContext.insert(
            PersonaLearningReceiptRecord(
                personaID: PersonaDefaults.professionalID, chatID: "chat", messageID: future.id
            )
        )
        try container.mainContext.save()
        XCTAssertTrue(try chats.personaLearningMessages(
            chatID: "chat", personaID: PersonaDefaults.professionalID, assignedAt: assignedAt
        ).isEmpty)
    }

    func testCurrentUsesSparseAdjustmentStorage() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedBuiltInsIfNeeded()

        try repository.setAdjustment(2, dimensionKey: "warmth", personaID: PersonaDefaults.professionalID)
        XCTAssertEqual(try repository.adjustments(personaID: PersonaDefaults.professionalID).map(\.adjustment), [2])

        try repository.setAdjustment(0, dimensionKey: "warmth", personaID: PersonaDefaults.professionalID)
        XCTAssertTrue(try repository.adjustments(personaID: PersonaDefaults.professionalID).isEmpty)
    }

    func testRegistryDefinitionsAreStableAndSelfContained() {
        let definitions = PersonaStyleDimensionRegistry.activeDefinitions
        XCTAssertEqual(Set(definitions.map(\.key)).count, definitions.count)
        XCTAssertEqual(definitions.map(\.order), definitions.map(\.order).sorted())
        for definition in definitions where !definition.observationOnly {
            XCTAssertEqual(definition.bandLabels.count, 5)
            XCTAssertEqual(definition.bandInstructions.count, 5)
            XCTAssertEqual(definition.adjustmentLabels.count, 5)
        }
    }

    func testResolverMakesLearnedVoicePrimaryAndNudgesBounded() {
        let learned = PersonaLearnedTrait(
            id: UUID(), dimensionKey: "formality", learnedLevel: 1,
            observation: "Uses polished phrasing", confidence: 1, evidenceCount: 8,
            origin: .userConfirmed, status: .active, updatedAt: Date()
        )

        let current = PersonaStyleResolver.resolve(
            baseline: ["formality": -1], adjustments: [:], traits: [learned]
        ).first { $0.dimensionKey == "formality" }
        let nudged = PersonaStyleResolver.resolve(
            baseline: ["formality": -1], adjustments: ["formality": -2], traits: [learned]
        ).first { $0.dimensionKey == "formality" }

        XCTAssertEqual(current?.shortLabel, "Very formal")
        XCTAssertEqual(current?.source, .userCorrected)
        XCTAssertEqual(nudged?.shortLabel, "Formal", "A maximum nudge should shift, not replace, a fully learned voice")
    }

    func testCurrentTracksNewLearnedEvidence() {
        func signal(level: Double) -> String? {
            PersonaStyleResolver.resolve(
                baseline: ["warmth": 0], adjustments: [:],
                traits: [PersonaLearnedTrait(
                    id: UUID(), dimensionKey: "warmth", learnedLevel: level,
                    observation: "", confidence: 1, evidenceCount: 8,
                    origin: .aiInferred, status: .active, updatedAt: Date()
                )]
            ).first { $0.dimensionKey == "warmth" }?.shortLabel
        }

        XCTAssertEqual(signal(level: -1), "Very reserved")
        XCTAssertEqual(signal(level: 1), "Very warm")
    }

    func testTraitReconciliationUsesBandsAndDeterministicConfidence() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedBuiltInsIfNeeded()
        let ids = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [PersonaTraitChange(
                dimensionKey: "formality", levelBand: .higher,
                observation: "Usually writes complete sentences", sourceMessageIDs: ids
            )],
            sampleMessageIDs: Set(ids), sampleCount: 2
        )

        let trait = try XCTUnwrap(personas.traits(personaID: PersonaDefaults.professionalID).first)
        XCTAssertEqual(trait.learnedLevel, 0.5)
        XCTAssertEqual(trait.confidence, 0.45, accuracy: 0.0001)
        XCTAssertEqual(trait.evidenceCount, 2)
    }

    func testUnknownAndMismatchedDimensionsAreIgnored() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedBuiltInsIfNeeded()
        let id = UUID()

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [
                PersonaTraitChange(
                    dimensionKey: "notRegistered", levelBand: .higher,
                    observation: "Unknown", sourceMessageIDs: [id]
                ),
                PersonaTraitChange(
                    dimensionKey: "vocabulary", levelBand: .higher,
                    observation: "Should have no level", sourceMessageIDs: [id]
                )
            ],
            sampleMessageIDs: [id], sampleCount: 1
        )

        XCTAssertTrue(try personas.traits(personaID: PersonaDefaults.professionalID).isEmpty)
    }

    func testConfirmedAndDismissedTraitsCannotBeOverwritten() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedBuiltInsIfNeeded()
        let confirmed = PersonaLearnedTraitRecord(
            personaID: PersonaDefaults.professionalID, dimensionKey: "warmth",
            learnedLevel: 1, observation: "My correction", confidence: 1,
            evidenceCount: 4, origin: PersonaTraitOrigin.userConfirmed.rawValue
        )
        let dismissed = PersonaLearnedTraitRecord(
            personaID: PersonaDefaults.professionalID, dimensionKey: "humor",
            learnedLevel: -1, observation: "Suppressed", confidence: 0.5,
            evidenceCount: 2, origin: PersonaTraitOrigin.aiInferred.rawValue,
            status: PersonaTraitStatus.dismissed.rawValue
        )
        container.mainContext.insert(confirmed)
        container.mainContext.insert(dismissed)
        try container.mainContext.save()
        let id = UUID()
        let changes = [
            PersonaTraitChange(
                dimensionKey: "warmth", levelBand: .muchLower,
                observation: "Overwrite", sourceMessageIDs: [id]
            ),
            PersonaTraitChange(
                dimensionKey: "humor", levelBand: .muchHigher,
                observation: "Restore", sourceMessageIDs: [id]
            )
        ]

        XCTAssertEqual(
            try chats.projectedPersonaPromptContext(
                personaID: PersonaDefaults.professionalID, changes: changes
            ),
            try chats.personaPromptContext(personaID: PersonaDefaults.professionalID)
        )

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: changes,
            sampleMessageIDs: [id], sampleCount: 1
        )

        XCTAssertEqual(confirmed.observation, "My correction")
        XCTAssertEqual(confirmed.learnedLevel, 1)
        XCTAssertEqual(dismissed.observation, "Suppressed")
        XCTAssertEqual(dismissed.status, PersonaTraitStatus.dismissed.rawValue)
    }

    func testPromptContainsResolvedSemanticsWithoutStyleFloats() throws {
        let context = PersonaPromptContext(
            id: PersonaDefaults.professionalID, name: "The Professional",
            purposeInstructions: "Write for work.",
            resolvedStyle: [PersonaResolvedStyleSignal(
                dimensionKey: "formality", title: "Formality", shortLabel: "Formal",
                descriptor: "formal", instruction: "Use polished, complete phrasing.", source: .learnedVoice
            )],
            descriptiveObservations: [], alwaysFollowRules: "Never use emoji.",
            registryVersion: PersonaStyleDimensionRegistry.version,
            resolverVersion: PersonaStyleResolver.version
        )
        let request = SuggestedReplyGenerationRequest(
            chatName: "Chat", relationshipSubtitle: "", contactMemories: [],
            currentInteractionGoal: "", persona: context, personaLearningMessages: [],
            existingHistorySummary: "", summaryMode: .unchanged,
            olderMessagesToSummarize: [], recentMessages: [], traceID: ImportTraceID()
        )

        let input = SuggestedReplyPrompt.input(for: request)
        XCTAssertTrue(input.contains("Use polished, complete phrasing."))
        XCTAssertTrue(input.contains("Never use emoji."))
        XCTAssertFalse(input.contains("learnedLevel"))
        XCTAssertFalse(input.contains("confidence"))
        XCTAssertFalse(input.contains("baselineStyle"))
    }

    func testTraitDecoderRequiresBandOnlyForAxisDimensions() throws {
        let id = UUID().uuidString
        let valid = """
        {"historySummary":"","replies":["One","Two"],"memoryChanges":[],"personaTraitChanges":[
          {"dimensionKey":"formality","levelBand":"higher","observation":"Uses complete sentences","sourceMessageIDs":["\(id)"]},
          {"dimensionKey":"vocabulary","levelBand":null,"observation":"Often says sounds good","sourceMessageIDs":["\(id)"]}
        ]}
        """
        let result = try SuggestedReplyResultDecoder.decode(content: valid, finishReason: "stop")
        XCTAssertEqual(result.personaTraitChanges.map(\.dimensionKey), ["formality", "vocabulary"])

        let invalid = valid.replacingOccurrences(of: "\"dimensionKey\":\"formality\",\"levelBand\":\"higher\"", with: "\"dimensionKey\":\"formality\",\"levelBand\":null")
        XCTAssertThrowsError(try SuggestedReplyResultDecoder.decode(content: invalid, finishReason: "stop"))
    }

    private func message(chatID: String, sender: String, createdAt: Date) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID, senderKind: sender, text: "Example", normalizedText: "example",
            timeLabel: "", sortIndex: 0, createdAt: createdAt
        )
    }
}
