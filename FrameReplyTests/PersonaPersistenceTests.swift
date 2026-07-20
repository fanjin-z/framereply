import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class PersonaPersistenceTests: XCTestCase {
    func testSeedingAndSelectedDefaultsDriveNewContexts() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let originalIDs = try repository.personas().map(\.id)
        try repository.seedPersonasIfNeeded()

        let personas = try repository.personas()
        XCTAssertEqual(personas.map(\.name), ["Professional", "Spark", "Thoughtful"])
        XCTAssertEqual(
            personas.compactMap(\.builtInID),
            [.professional, .spark, .thoughtful]
        )
        XCTAssertEqual(personas.map(\.id), originalIDs)
        XCTAssertEqual(Set(personas.map(\.id)).count, 3)
        let professional = try XCTUnwrap(personas.first { $0.builtInID == .professional })
        XCTAssertEqual(try repository.defaultPersonaID(), professional.id)
        XCTAssertFalse(try repository.observations(personaID: professional.id).isEmpty)

        let thoughtful = try XCTUnwrap(personas.first { $0.builtInID == .thoughtful })
        let chats = ChatRepository(container: container)
        try repository.setDefaultPersona(id: thoughtful.id)
        XCTAssertEqual(try chats.chatContextValue(chatID: "new-chat").personaID, thoughtful.id)
        XCTAssertEqual(try chats.personaPromptContext(personaID: UUID()).id, thoughtful.id)
    }

    func testDefaultResolutionRejectsMissingMalformedAndDanglingMetadata() throws {
        let invalidValues: [String?] = [nil, "not-a-uuid", UUID().uuidString]
        for value in invalidValues {
            let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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

    func testPersonaCreateDuplicateAndDeleteLifecycle() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = PersonaRepository(container: container)
        try repository.seedPersonasIfNeeded()
        let observation = PersonaRepository.makeObservation(
            text: "Uses short sentences.", origin: .user,
            isUserProtected: true
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
        XCTAssertEqual(copied.status, PersonaObservationStatus.active.rawValue)

        let professional = try XCTUnwrap(
            try repository.personas().first { $0.builtInID == .professional })
        let spark = try XCTUnwrap(
            try repository.personas().first { $0.builtInID == .spark })
        let assignment = ChatContextRecord(
            chatID: "chat", currentInteractionGoal: "",
            personaID: professional.id
        )
        container.mainContext.insert(assignment)
        try container.mainContext.save()

        XCTAssertThrowsError(try repository.delete(professional))
        try repository.delete(professional, replacementDefaultID: spark.id)

        XCTAssertEqual(try repository.defaultPersonaID(), spark.id)
        XCTAssertEqual(assignment.personaID, spark.id)

        let thoughtful = try XCTUnwrap(
            try repository.personas().first { $0.builtInID == .thoughtful })
        try repository.setDefaultPersona(id: thoughtful.id)
        let nonDefaultAssignment = ChatContextRecord(
            chatID: "other-chat", currentInteractionGoal: "",
            personaID: duplicate.id
        )
        container.mainContext.insert(nonDefaultAssignment)
        try container.mainContext.save()

        try repository.delete(duplicate)
        XCTAssertEqual(nonDefaultAssignment.personaID, thoughtful.id)
        XCTAssertNil(try repository.persona(id: duplicate.id))
    }

    func testLearningUsesOnlyFutureUnprocessedUserMessages() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let personas = PersonaRepository(container: container)
        let chats = ChatRepository(container: container)
        try personas.seedPersonasIfNeeded()
        let personaID = try personas.defaultPersonaID()
        let assignedAt = Date()
        let old = message(
            chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(-1))
        let otherParticipant = message(
            chatID: "chat",
            sender: "other_participant",
            createdAt: assignedAt.addingTimeInterval(1)
        )
        let future = message(
            chatID: "chat", sender: "user", createdAt: assignedAt.addingTimeInterval(2))
        container.mainContext.insert(old)
        container.mainContext.insert(otherParticipant)
        container.mainContext.insert(future)
        try container.mainContext.save()

        XCTAssertEqual(
            try chats.personaLearningMessages(
                chatID: "chat", personaID: personaID, assignedAt: assignedAt
            ).map(\.id), [future.id])
    }

    func testObservationReconciliationHonorsEvidenceAndProtectedTombstones() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
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

        try personas.addUserObservation("Never uses exclamation marks.", personaID: personaID)
        let protected = try XCTUnwrap(
            personas.observations(personaID: personaID)
                .first { $0.text == "Never uses exclamation marks." })
        try personas.archiveObservation(protected)
        let protectedEvidenceIDs = [UUID(), UUID()]

        try chats.savePersonaExampleAnalysis(
            personaID: personaID,
            changes: [
                PersonaObservationChange(
                    action: .update, targetObservationID: protected.id,
                    text: "Uses lots of exclamation marks!",
                    sourceMessageIDs: protectedEvidenceIDs
                ),
                PersonaObservationChange(
                    action: .add, targetObservationID: nil,
                    text: "Never uses exclamation marks.",
                    sourceMessageIDs: protectedEvidenceIDs
                )
            ], sampleMessageIDs: Set(protectedEvidenceIDs), sampleCount: 2
        )

        let all = try personas.observations(personaID: personaID, includeInactive: true)
        XCTAssertEqual(all.filter { $0.text == "Never uses exclamation marks." }.count, 1)
        XCTAssertFalse(all.contains { $0.text == "Uses lots of exclamation marks!" })
    }

    private func message(chatID: String, sender: String, createdAt: Date) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID, senderKind: sender, text: "Example",
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
