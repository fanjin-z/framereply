import XCTest

@testable import zeptly

final class ChatMemoryReconcilerTests: XCTestCase {
    func testAddsUpdatesSupersedesAndArchivesWithValidEvidence() throws {
        let evidenceID = UUID()
        let aiID = UUID()
        let userID = UUID()
        let archivedID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let memories = [
            ChatMemory(
                id: aiID,
                text: "Likes tea",
                origin: .ai,
                certainty: .aiInferred
            ),
            ChatMemory(id: userID, text: "Lives in Paris"),
            ChatMemory(
                id: archivedID,
                text: "Conference next week",
                origin: .ai,
                certainty: .aiInferred
            )
        ]

        let result = ChatMemoryReconciler.reconcile(
            memories: memories,
            changes: [
                ChatMemoryChange(
                    action: .update,
                    targetMemoryID: aiID,
                    text: "Prefers coffee",
                    sourceMessageIDs: [evidenceID]
                ),
                ChatMemoryChange(
                    action: .update,
                    targetMemoryID: userID,
                    text: "Now lives in Berlin",
                    sourceMessageIDs: [evidenceID]
                ),
                ChatMemoryChange(
                    action: .archive,
                    targetMemoryID: archivedID,
                    text: nil,
                    sourceMessageIDs: [evidenceID]
                ),
                ChatMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: "Vegetarian",
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedOtherParticipantSourceMessageIDs: [evidenceID],
            now: now
        )

        let updatedAI = try XCTUnwrap(result.first { $0.id == aiID })
        XCTAssertEqual(updatedAI.text, "Prefers coffee")
        XCTAssertEqual(updatedAI.status, .active)

        let supersededUser = try XCTUnwrap(result.first { $0.id == userID })
        XCTAssertEqual(supersededUser.status, .superseded)
        let replacement = try XCTUnwrap(result.first { $0.text == "Now lives in Berlin" })
        XCTAssertEqual(replacement.origin, .ai)
        XCTAssertEqual(replacement.certainty, .aiInferred)
        XCTAssertEqual(replacement.createdAt, now)

        XCTAssertEqual(result.first { $0.id == archivedID }?.status, .archived)
        XCTAssertNotNil(result.first { $0.text == "Vegetarian" && $0.status == .active })
    }

    func testRejectsInvalidEvidenceTargetsAndDuplicateAdds() {
        let allowedID = UUID()
        let memory = ChatMemory(text: "Vegetarian")
        let result = ChatMemoryReconciler.reconcile(
            memories: [memory],
            changes: [
                ChatMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: " vegetarian. ",
                    sourceMessageIDs: [allowedID]
                ),
                ChatMemoryChange(
                    action: .archive,
                    targetMemoryID: UUID(),
                    text: nil,
                    sourceMessageIDs: [allowedID]
                ),
                ChatMemoryChange(
                    action: .archive,
                    targetMemoryID: memory.id,
                    text: nil,
                    sourceMessageIDs: [UUID()]
                )
            ],
            allowedOtherParticipantSourceMessageIDs: [allowedID]
        )

        XCTAssertEqual(result, [memory])

        let otherParticipantID = UUID()
        let disallowedID = UUID()
        let mixedEvidenceResult = ChatMemoryReconciler.reconcile(
            memories: [],
            changes: [
                ChatMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: "Asked about partner hotels",
                    sourceMessageIDs: [otherParticipantID, disallowedID]
                )
            ],
            allowedOtherParticipantSourceMessageIDs: [otherParticipantID]
        )

        XCTAssertTrue(mixedEvidenceResult.isEmpty)
    }
}
