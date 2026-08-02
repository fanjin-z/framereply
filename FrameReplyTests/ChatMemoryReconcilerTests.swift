import XCTest

@testable import FrameReply

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

    func testEnforcesReadableAIMemoryLimitWithoutChangingExistingManualMemory() throws {
        let evidenceID = UUID()
        let manualMemory = ChatMemory(
            text: String(
                repeating: "u", count: ChatMemoryLimits.maximumAITextCodePoints + 40)
        )
        let aiMemory = ChatMemory(
            text: "Likes tea",
            origin: .ai,
            certainty: .aiInferred
        )
        let acceptedText = String(repeating: "a", count: 118) + "e\u{301}"
        let rejectedText = String(repeating: "b", count: 119) + "e\u{301}"
        XCTAssertEqual(acceptedText.unicodeScalars.count, 120)
        XCTAssertEqual(rejectedText.count, 120)
        XCTAssertEqual(rejectedText.unicodeScalars.count, 121)

        let result = ChatMemoryReconciler.reconcile(
            memories: [manualMemory, aiMemory],
            changes: [
                ChatMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: acceptedText,
                    sourceMessageIDs: [evidenceID]
                ),
                ChatMemoryChange(
                    action: .add,
                    targetMemoryID: nil,
                    text: rejectedText,
                    sourceMessageIDs: [evidenceID]
                ),
                ChatMemoryChange(
                    action: .update,
                    targetMemoryID: aiMemory.id,
                    text: rejectedText,
                    sourceMessageIDs: [evidenceID]
                )
            ],
            allowedOtherParticipantSourceMessageIDs: [evidenceID]
        )

        XCTAssertEqual(
            try XCTUnwrap(result.first { $0.id == manualMemory.id }).text,
            manualMemory.text
        )
        XCTAssertEqual(
            try XCTUnwrap(result.first { $0.id == aiMemory.id }).text,
            aiMemory.text
        )
        XCTAssertNotNil(result.first { $0.text == acceptedText })
        XCTAssertNil(result.first { $0.text == rejectedText })
    }
}
