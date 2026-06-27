import Foundation
import XCTest
@testable import zeptly

final class ShortcutResponsePayloadTests: XCTestCase {
    func testSuccessPayloadIncludesImportContract() throws {
        let payload = ShortcutResponsePayload(
            status: .success,
            message: "Imported",
            chatID: "chat-id",
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
        XCTAssertEqual(object["matchedExisting"] as? Bool, true)
        XCTAssertEqual(object["insertedMessageCount"] as? Int, 2)
    }
}
