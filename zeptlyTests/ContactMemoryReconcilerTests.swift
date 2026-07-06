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
                origin: .ai,
                certainty: .aiInferred
            ),
            ContactMemory(id: userID, text: "Lives in Paris"),
            ContactMemory(
                id: archivedID,
                text: "Conference next week",
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
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .update,
                    targetMemoryID: userID,
                    text: "Now lives in Berlin",
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: archivedID,
                    text: nil,
                    sourceMessageIDs: [evidenceID]
                ),
                ContactMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: "Vegetarian",
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedContactSourceMessageIDs: [evidenceID],
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
        let memory = ContactMemory(text: "Vegetarian")
        let result = ContactMemoryReconciler.reconcile(
            memories: [memory],
            changes: [
                ContactMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: " vegetarian. ",
                    sourceMessageIDs: [allowedID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: UUID(),
                    text: nil,
                    sourceMessageIDs: [allowedID]
                ),
                ContactMemoryChange(
                    action: .archive,
                    targetMemoryID: memory.id,
                    text: nil,
                    sourceMessageIDs: [UUID()]
                )
            ],
            allowedContactSourceMessageIDs: [allowedID]
        )

        XCTAssertEqual(result, [memory])
    }

    func testRejectsOperationWhenAnyEvidenceIsNotContactAuthored() {
        let contactID = UUID()
        let disallowedID = UUID()
        let result = ContactMemoryReconciler.reconcile(
            memories: [],
            changes: [
                ContactMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: "Asked about partner hotels",
                    sourceMessageIDs: [contactID, disallowedID]
                )
            ],
            allowedContactSourceMessageIDs: [contactID]
        )

        XCTAssertTrue(result.isEmpty)
    }
}
