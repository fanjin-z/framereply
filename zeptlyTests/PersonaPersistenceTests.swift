import SwiftData
import XCTest

@testable import zeptly

@MainActor
final class PersonaPersistenceTests: XCTestCase {
    func testSeedingIsIdempotentAndCreatesDefaultWithObservations() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        try repository.seedPersonasIfNeeded()

        XCTAssertEqual(
            try repository.personas().map(\.name),
            [
                "Professional", "Spark", "Thoughtful"
            ])
        XCTAssertEqual(try repository.defaultPersonaID(), PersonaDefaults.professionalID)
        XCTAssertFalse(try repository.observations(personaID: PersonaDefaults.professionalID).isEmpty)
    }

    func testQuickSetupCompilesTextOnlyAndReplacesPriorQuickObservation() {
        let first = PersonaQuickSetup.compile(selections: ["formality": 2, "emoji": -2])
        XCTAssertEqual(first.count, 2)
        XCTAssertTrue(first.contains("Does not use emoji."))

        let replaced = PersonaQuickSetup.replacingQuickSetupObservations(
            in: first + ["Uses sentence fragments."],
            selections: ["formality": -1]
        )
        XCTAssertFalse(replaced.contains("Does not use emoji."))
        XCTAssertTrue(replaced.contains("Keeps wording casual and conversational."))
        XCTAssertTrue(replaced.contains("Uses sentence fragments."))
    }

    func testCreateAndDuplicatePersistOnlyObservationText() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let observation = PersonaRepository.makeObservation(
            text: "Uses short sentences.", origin: .user,
            isUserProtected: true, evidenceSource: .user
        )
        let created = try repository.create(
            name: "Weekend", summary: "Casual", instructions: "Sound natural.",
            observations: [observation]
        )
        let duplicate = try repository.duplicate(created)

        XCTAssertEqual(duplicate.summary, "Casual")
        XCTAssertEqual(duplicate.instructions, "Sound natural.")
        let copied = try XCTUnwrap(repository.observations(personaID: duplicate.id).first)
        XCTAssertEqual(copied.text, "Uses short sentences.")
        XCTAssertEqual(copied.origin, PersonaObservationOrigin.seed.rawValue)
        XCTAssertFalse(copied.isUserProtected)
        XCTAssertEqual(copied.sourceMessageIDsJSON, "[]")
    }

    func testDeletingDefaultRequiresAndAppliesReplacement() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let professional = try XCTUnwrap(repository.persona(id: PersonaDefaults.professionalID))
        let assignment = ContactContextRecord(
            chatID: "chat", relationshipSubtitle: "", currentInteractionGoal: "",
            personaID: professional.id
        )
        container.mainContext.insert(assignment)
        try container.mainContext.save()

        XCTAssertThrowsError(try repository.delete(professional))
        try repository.delete(professional, replacementDefaultID: PersonaDefaults.sparkID)

        XCTAssertEqual(try repository.defaultPersonaID(), PersonaDefaults.sparkID)
        XCTAssertEqual(assignment.personaID, PersonaDefaults.sparkID)
    }

    func testLearningUsesOnlyFutureUnprocessedUserMessages() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
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
            ).map(\.id), [future.id])
    }

    func testObservationReconciliationAddsUpdatesAndArchivesWithEvidence() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
        let ids = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [
                PersonaObservationChange(
                    action: .add, targetObservationID: nil,
                    text: "Often uses sentence fragments.", sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )
        let added = try XCTUnwrap(
            personas.observations(personaID: PersonaDefaults.professionalID)
                .first { $0.text == "Often uses sentence fragments." })

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [
                PersonaObservationChange(
                    action: .update, targetObservationID: added.id,
                    text: "Usually writes in sentence fragments.", sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )
        XCTAssertEqual(added.status, PersonaObservationStatus.superseded.rawValue)
        let replacement = try XCTUnwrap(
            personas.observations(personaID: PersonaDefaults.professionalID)
                .first { $0.text == "Usually writes in sentence fragments." })

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [
                PersonaObservationChange(
                    action: .archive, targetObservationID: replacement.id,
                    text: nil, sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )
        XCTAssertEqual(replacement.status, PersonaObservationStatus.archived.rawValue)
    }

    func testProtectedObservationAndTombstoneCannotBeChangedOrRecreated() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
        try personas.addUserObservation("Never uses exclamation marks.", personaID: PersonaDefaults.professionalID)
        let protected = try XCTUnwrap(
            personas.observations(personaID: PersonaDefaults.professionalID)
                .first { $0.text == "Never uses exclamation marks." })
        try personas.archiveObservation(protected)
        let ids = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: PersonaDefaults.professionalID,
            changes: [
                PersonaObservationChange(
                    action: .update, targetObservationID: protected.id,
                    text: "Uses lots of exclamation marks!", sourceMessageIDs: ids
                ),
                PersonaObservationChange(
                    action: .add, targetObservationID: nil,
                    text: "Never uses exclamation marks.", sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )

        let all = try personas.observations(personaID: PersonaDefaults.professionalID, includeInactive: true)
        XCTAssertEqual(all.filter { $0.text == "Never uses exclamation marks." }.count, 1)
        XCTAssertFalse(all.contains { $0.text == "Uses lots of exclamation marks!" })
    }

    func testPromptContainsInstructionsAndObservationTextOnly() {
        let observation = PersonaRepository.makeObservation(
            text: "Uses concise sentences.", origin: .seed,
            isUserProtected: false, evidenceSource: .seed
        )
        let context = PersonaPromptContext(
            id: UUID(), name: "Test", instructions: "Write naturally.",
            observations: [observation], protectedTombstones: []
        )
        let request = SuggestedReplyGenerationRequest(
            chatName: "Chat", relationshipSubtitle: "", contactMemories: [],
            currentInteractionGoal: "", persona: context, personaLearningMessages: [],
            existingHistorySummary: "", summaryMode: .unchanged,
            olderMessagesToSummarize: [], recentMessages: [], traceID: ImportTraceID()
        )
        let input = SuggestedReplyPrompt.input(for: request)
        XCTAssertTrue(input.contains("Write naturally."))
        XCTAssertTrue(input.contains("Uses concise sentences."))
        XCTAssertFalse(input.contains("dimensionKey"))
        XCTAssertFalse(input.contains("learnedLevel"))
    }

    func testObservationDecoderRequiresTwoDistinctEvidenceMessages() throws {
        let first = UUID().uuidString
        let second = UUID().uuidString
        let valid = """
            {"historySummary":"","replies":["One","Two"],"memoryChanges":[],
             "personaObservationChanges":[{"action":"add","targetObservationID":null,
             "text":"Uses short sentences.","evidenceMessageIDs":["\(first)","\(second)"]}]}
            """
        let result = try SuggestedReplyResultDecoder.decode(content: valid, finishReason: "stop")
        XCTAssertEqual(result.personaObservationChanges.first?.text, "Uses short sentences.")

        let invalid = valid.replacingOccurrences(of: "\"\(second)\"", with: "\"\(first)\"")
        XCTAssertThrowsError(try SuggestedReplyResultDecoder.decode(content: invalid, finishReason: "stop"))
    }

    private func message(chatID: String, sender: String, createdAt: Date) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID, senderKind: sender, text: "Example", normalizedText: "example",
            timeLabel: "", sortIndex: 0, createdAt: createdAt
        )
    }
}
