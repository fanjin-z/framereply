import SwiftData
import XCTest

@testable import zeptly

@MainActor
final class PersonaPersistenceTests: XCTestCase {
    func testSeedingIsIdempotentAndCreatesDefaultWithObservations() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let originalIDs = try repository.personas().map(\.id)
        try repository.seedPersonasIfNeeded()

        let personas = try repository.personas()
        XCTAssertEqual(personas.map(\.name), ["Professional", "Spark", "Thoughtful"])
        XCTAssertEqual(personas.map(\.id), originalIDs)
        XCTAssertEqual(Set(personas.map(\.id)).count, 3)
        let professional = try XCTUnwrap(personas.first { $0.name == "Professional" })
        XCTAssertEqual(try repository.defaultPersonaID(), professional.id)
        XCTAssertFalse(try repository.observations(personaID: professional.id).isEmpty)
    }

    func testDefaultResolutionRejectsMissingMalformedAndDanglingMetadata() throws {
        let invalidValues: [String?] = [nil, "not-a-uuid", UUID().uuidString]
        for value in invalidValues {
            let container = try ZeptlyDataStore.makeContainer(inMemory: true)
            let repository = PersonaRepository(container: container)
            try repository.seedPersonasIfNeeded()
            let metadata = try XCTUnwrap(defaultMetadata(in: container))
            if let value {
                metadata.value = value
            } else {
                container.mainContext.delete(metadata)
            }
            try container.mainContext.save()

            XCTAssertThrowsError(try repository.defaultPersonaID()) {
                XCTAssertEqual($0 as? PersonaRepositoryError, .invalidDefaultPersona)
            }
        }
    }

    func testSelectedDefaultDrivesNewContextsAndMissingPersonaFallback() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        let thoughtful = try XCTUnwrap(try personas.personas().first { $0.name == "Thoughtful" })
        try personas.setDefaultPersona(id: thoughtful.id)

        XCTAssertEqual(try chats.contactContextValue(chatID: "new-chat").personaID, thoughtful.id)
        XCTAssertEqual(try chats.personaPromptContext(personaID: UUID()).id, thoughtful.id)
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
        let records = try repository.personas()
        let professional = try XCTUnwrap(records.first { $0.name == "Professional" })
        let spark = try XCTUnwrap(records.first { $0.name == "Spark" })
        let assignment = ContactContextRecord(
            chatID: "chat", relationshipSubtitle: "", currentInteractionGoal: "",
            personaID: professional.id
        )
        container.mainContext.insert(assignment)
        try container.mainContext.save()

        XCTAssertThrowsError(try repository.delete(professional))
        try repository.delete(professional, replacementDefaultID: spark.id)

        XCTAssertEqual(try repository.defaultPersonaID(), spark.id)
        XCTAssertEqual(assignment.personaID, spark.id)
    }

    func testDeletingNonDefaultReassignsContactsToDesignatedDefault() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let records = try repository.personas()
        let professional = try XCTUnwrap(records.first { $0.name == "Professional" })
        let spark = try XCTUnwrap(records.first { $0.name == "Spark" })
        let thoughtful = try XCTUnwrap(records.first { $0.name == "Thoughtful" })
        try repository.setDefaultPersona(id: thoughtful.id)
        let assignment = ContactContextRecord(
            chatID: "chat", relationshipSubtitle: "", currentInteractionGoal: "",
            personaID: spark.id
        )
        container.mainContext.insert(assignment)
        try container.mainContext.save()

        try repository.delete(spark)

        XCTAssertEqual(try repository.defaultPersonaID(), thoughtful.id)
        XCTAssertEqual(assignment.personaID, thoughtful.id)
        XCTAssertNotNil(try repository.persona(id: professional.id))
        XCTAssertNil(try repository.persona(id: spark.id))
    }

    func testLearningUsesOnlyFutureUnprocessedUserMessages() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
        let personaID = try personas.defaultPersonaID()
        let assignedAt = Date()
        let old = message(
            chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(-1))
        let contact = message(
            chatID: "chat", sender: "contact", createdAt: assignedAt.addingTimeInterval(1))
        let future = message(
            chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(2))
        container.mainContext.insert(old)
        container.mainContext.insert(contact)
        container.mainContext.insert(future)
        try container.mainContext.save()

        XCTAssertEqual(
            try chats.personaLearningMessages(
                chatID: "chat", personaID: personaID, assignedAt: assignedAt
            ).map(\.id), [future.id])
    }

    func testObservationReconciliationAddsUpdatesAndArchivesWithEvidence() throws {
        let container = try ZeptlyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
        let personaID = try personas.defaultPersonaID()
        let ids = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: personaID,
            changes: [
                PersonaObservationChange(
                    action: .add, targetObservationID: nil,
                    text: "Often uses sentence fragments.", sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )
        let added = try XCTUnwrap(
            personas.observations(personaID: personaID)
                .first { $0.text == "Often uses sentence fragments." })

        try chats.savePersonaExampleAnalysis(
            personaID: personaID,
            changes: [
                PersonaObservationChange(
                    action: .update, targetObservationID: added.id,
                    text: "Usually writes in sentence fragments.", sourceMessageIDs: ids
                )
            ], sampleMessageIDs: Set(ids), sampleCount: 2
        )
        XCTAssertEqual(added.status, PersonaObservationStatus.superseded.rawValue)
        let replacement = try XCTUnwrap(
            personas.observations(personaID: personaID)
                .first { $0.text == "Usually writes in sentence fragments." })

        try chats.savePersonaExampleAnalysis(
            personaID: personaID,
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
        let personaID = try personas.defaultPersonaID()
        try personas.addUserObservation("Never uses exclamation marks.", personaID: personaID)
        let protected = try XCTUnwrap(
            personas.observations(personaID: personaID)
                .first { $0.text == "Never uses exclamation marks." })
        try personas.archiveObservation(protected)
        let ids = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: personaID,
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

        let all = try personas.observations(personaID: personaID, includeInactive: true)
        XCTAssertEqual(all.filter { $0.text == "Never uses exclamation marks." }.count, 1)
        XCTAssertFalse(all.contains { $0.text == "Uses lots of exclamation marks!" })
    }

    func testObservationDecoderRequiresTwoDistinctEvidenceMessages() throws {
        let first = UUID().uuidString
        let second = UUID().uuidString
        let valid = """
            {"historySummary":"","replies":["One","Two"],
             "conversationStrategy":"Reply briefly while preserving the style sample.",
             "strategyRationale":"This fixture validates persona evidence decoding.",
             "memoryChanges":[],
             "personaObservationChanges":[{"action":"add","targetObservationID":null,
             "text":"Uses short sentences.","evidenceMessageIDs":["\(first)","\(second)"]}]}
            """
        let result = try SuggestedReplyResultDecoder.decode(content: valid, finishReason: "stop")
        XCTAssertEqual(result.personaObservationChanges.first?.text, "Uses short sentences.")

        let invalid = valid.replacingOccurrences(of: "\"\(second)\"", with: "\"\(first)\"")
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(content: invalid, finishReason: "stop"))
    }

    private func message(chatID: String, sender: String, createdAt: Date) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID, senderKind: sender, text: "Example", normalizedText: "example",
            timeLabel: "", sortIndex: 0, createdAt: createdAt
        )
    }

    private func defaultMetadata(in container: ModelContainer) throws -> StoreMetadataRecord? {
        try container.mainContext.fetch(
            FetchDescriptor<StoreMetadataRecord>(
                predicate: #Predicate { $0.key == "defaultPersonaID" }
            )
        ).first
    }
}
