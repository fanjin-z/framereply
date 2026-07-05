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

    private func message(chatID: String, sender: String, createdAt: Date) -> ChatMessageRecord {
        ChatMessageRecord(
            chatID: chatID, senderKind: sender, text: "Example", normalizedText: "example",
            timeLabel: "", sortIndex: 0, createdAt: createdAt
        )
    }
}
