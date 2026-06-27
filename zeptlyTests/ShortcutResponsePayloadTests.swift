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

    func testMatchedImportPresentation() {
        let response = ShortcutResponseBuilder.success(
            outcome(matchedExisting: true, reviewRequired: false, duplicate: false, count: 2)
        )

        XCTAssertEqual(response.dialog, "Added 2 new messages to Sarah.")
        XCTAssertEqual(response.payload.status, .success)
    }

    func testProvisionalImportPresentation() {
        let response = ShortcutResponseBuilder.success(
            outcome(matchedExisting: false, reviewRequired: true, duplicate: false, count: 1)
        )

        XCTAssertEqual(response.dialog, "Imported 1 message as Sarah. Review it in Zeptly.")
    }

    func testDuplicateImportPresentation() {
        let response = ShortcutResponseBuilder.success(
            outcome(matchedExisting: true, reviewRequired: false, duplicate: true, count: 0)
        )

        XCTAssertEqual(response.dialog, "No new messages found in Sarah.")
    }

    func testProviderFailurePresentationIncludesCodeAndReference() {
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
    }

    func testOCRAndPersistenceFailureMappings() {
        let traceID = ImportTraceID(
            value: UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        )
        let ocr = ShortcutResponseBuilder.failure(
            message: "No readable text was found.",
            errorCode: "ocr_failed",
            traceID: traceID
        )
        let persistence = ShortcutResponseBuilder.failure(
            message: "The chat history could not be saved.",
            errorCode: "import_failed",
            traceID: traceID
        )

        XCTAssertEqual(ocr.payload.errorCode, "ocr_failed")
        XCTAssertEqual(persistence.payload.errorCode, "import_failed")
        XCTAssertTrue(ocr.json.contains("\"diagnosticID\":\"ABCDEF12\""))
        XCTAssertTrue(persistence.dialog.contains("Reference ABCDEF12"))
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
