import Foundation
import XCTest

@testable import zeptly

final class ShortcutResponsePayloadTests: XCTestCase {
    func testSuccessPayloadIncludesImportContract() throws {
        let payload = ShortcutResponsePayload(
            status: .success,
            message: "Imported",
            diagnosticID: "ABC12345",
            chatID: "chat-id",
            chatName: "Sarah",
            importID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            matchedExisting: true,
            reviewRequired: false,
            duplicate: false,
            insertedMessageCount: 2,
            errorCode: nil
        )

        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["status"] as? String, "success")
        XCTAssertEqual(object["chatID"] as? String, "chat-id")
        XCTAssertEqual(object["chatName"] as? String, "Sarah")
        XCTAssertEqual(object["diagnosticID"] as? String, "ABC12345")
        XCTAssertEqual(object["matchedExisting"] as? Bool, true)
        XCTAssertEqual(object["insertedMessageCount"] as? Int, 2)
    }

    func testSuccessPresentationStates() {
        let cases: [(Bool, Bool, Bool, Int, String)] = [
            (true, false, false, 2, "Added 2 new messages to Sarah."),
            (false, true, false, 1, "Imported 1 message as Sarah. Review it in Zeptly."),
            (true, false, true, 0, "No new messages found in Sarah.")
        ]

        for (matchedExisting, reviewRequired, duplicate, count, expectedDialog) in cases {
            let response = ShortcutResponseBuilder.success(
                outcome(
                    matchedExisting: matchedExisting,
                    reviewRequired: reviewRequired,
                    duplicate: duplicate,
                    count: count
                )
            )

            XCTAssertEqual(response.dialog, expectedDialog)
            XCTAssertEqual(response.payload.status, .success)
        }
    }

    func testFailurePresentationIncludesCodeAndReference() {
        let traceID = ImportTraceID(
            value: UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        )
        let response = ShortcutResponseBuilder.failure(
            message: "The provider response did not match the chat format.",
            errorCode: "provider_schema_mismatch",
            traceID: traceID
        )

        XCTAssertEqual(response.payload.errorCode, "provider_schema_mismatch")
        XCTAssertEqual(response.payload.diagnosticID, "ABCDEF12")
        XCTAssertTrue(response.dialog.hasSuffix("Reference ABCDEF12."))
        XCTAssertTrue(response.json.contains("\"diagnosticID\":\"ABCDEF12\""))
    }

    private func outcome(
        matchedExisting: Bool,
        reviewRequired: Bool,
        duplicate: Bool,
        count: Int
    ) -> ScreenshotImportOutcome {
        ScreenshotImportOutcome(
            chatID: "chat-id",
            chatName: "Sarah",
            importID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            diagnosticID: "ABC12345",
            matchedExisting: matchedExisting,
            reviewRequired: reviewRequired,
            duplicate: duplicate,
            insertedMessageCount: count
        )
    }
}
