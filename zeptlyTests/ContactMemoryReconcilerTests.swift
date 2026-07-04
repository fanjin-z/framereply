import XCTest

@testable import zeptly

final class ContactMemoryReconcilerTests: XCTestCase {
    func testAddsUpdatesSupersedesAndArchivesWithValidEvidence() throws {
        let evidenceID = UUID()
        let aiID = UUID()
        let userID = UUID()
        let archivedID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let memories = [
            ContactMemory(
                id: aiID,
                text: "Likes tea",
                kind: .preference,
                origin: .ai,
                certainty: .aiInferred
            ),
            ContactMemory(id: userID, text: "Lives in Paris", kind: .fact),
            ContactMemory(
                id: archivedID,
                text: "Conference next week",
                kind: .event,
                origin: .ai,
                certainty: .aiInferred
            )
        ]

        let result = ContactMemoryReconciler.reconcile(
            memories: memories,
            changes: [
                ContactMemoryChange(
                    action: .update,
                    targetMemoryID: aiID,
                    text: "Prefers coffee",
                    kind: .preference,
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .update,
                    targetMemoryID: userID,
                    text: "Now lives in Berlin",
                    kind: .fact,
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: archivedID,
                    text: nil,
                    kind: nil,
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: "Vegetarian",
                    kind: .preference,
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedSourceMessageIDs: [evidenceID],
            now: now
        )

        let updatedAI = try XCTUnwrap(result.first { $0.id == aiID })
        XCTAssertEqual(updatedAI.text, "Prefers coffee")
        XCTAssertEqual(updatedAI.status, .active)
        XCTAssertEqual(updatedAI.sourceMessageIDs, [evidenceID])

        let supersededUser = try XCTUnwrap(result.first { $0.id == userID })
        XCTAssertEqual(supersededUser.status, .superseded)
        let replacement = try XCTUnwrap(result.first { $0.text == "Now lives in Berlin" })
        XCTAssertEqual(replacement.origin, .ai)
        XCTAssertEqual(replacement.certainty, .aiInferred)
        XCTAssertEqual(replacement.createdAt, now)

        XCTAssertEqual(result.first { $0.id == archivedID }?.status, .archived)
        XCTAssertNotNil(result.first { $0.text == "Vegetarian" && $0.status == .active })
    }

    func testRejectsUnknownEvidenceTargetsAndDuplicateAdds() {
        let allowedID = UUID()
        let memory = ContactMemory(text: "Vegetarian", kind: .preference)
        let result = ContactMemoryReconciler.reconcile(
            memories: [memory],
            changes: [
                ContactMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: " vegetarian. ",
                    kind: .preference,
                    sourceMessageIDs: [allowedID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: UUID(),
                    text: nil,
                    kind: nil,
                    sourceMessageIDs: [allowedID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: memory.id,
                    text: nil,
                    kind: nil,
                    sourceMessageIDs: [UUID()]
                )
            ],
            allowedSourceMessageIDs: [allowedID]
        )

        XCTAssertEqual(result, [memory])
    }
}
