import Foundation
import XCTest
@testable import zeptly

final class ChatImportAnalysisDecoderTests: XCTestCase {
    func testDecodesExactAndFencedJSON() throws {
        let exact = validJSON()
        XCTAssertEqual(try decode(exact).messages.first?.text, "Hello")
        XCTAssertEqual(try decode("\u{FEFF}  ```json\n\(exact)\n```  ").messages.first?.text, "Hello")
    }

    func testClassifiesEmptyTruncatedAndMalformedResponses() {
        assertFailure(nil, finishReason: "stop", kind: .emptyResponse)
        assertFailure(validJSON(), finishReason: "length", kind: .truncatedResponse)
        assertFailure("{not json", finishReason: "stop", kind: .invalidJSON)
    }

    func testClassifiesMissingAndWrongFieldsWithCodingPaths() {
        let missing = validJSON().replacingOccurrences(of: ",\"matchConfidence\":0.9", with: "")
        assertFailure(missing, kind: .schemaMismatch, path: "matchConfidence")

        let wrong = validJSON().replacingOccurrences(of: #""sender":"contact""#, with: #""sender":42"#)
        assertFailure(wrong, kind: .schemaMismatch, path: "messages[0].sender")
    }

    func testClassifiesUnknownCandidateAndIncompleteMessages() {
        let unknown = validJSON().replacingOccurrences(of: #""matchedChatID":null"#, with: #""matchedChatID":"unknown""#)
        assertFailure(unknown, kind: .invalidCandidateID, path: "matchedChatID")

        let incomplete = validJSON().replacingOccurrences(of: #""text":"Hello""#, with: #""text":"   ""#)
        assertFailure(incomplete, kind: .incompleteMessages, path: "messages")
    }

    private func decode(_ content: String, finishReason: String? = "stop") throws -> ChatImportAnalysis {
        try ChatImportAnalysisDecoder.decode(
            content: content,
            finishReason: finishReason,
            candidateIDs: ["known"]
        )
    }

    private func assertFailure(
        _ content: String?,
        finishReason: String? = "stop",
        kind: StructuredOutputFailureKind,
        path: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try ChatImportAnalysisDecoder.decode(
                content: content,
                finishReason: finishReason,
                candidateIDs: ["known"]
            )
            XCTFail("Expected \(kind)", file: file, line: line)
        } catch let failure as StructuredOutputFailure {
            XCTAssertEqual(failure.kind, kind, file: file, line: line)
            XCTAssertEqual(failure.codingPath, path, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func validJSON() -> String {
        #"{"conversationTitle":"Alex","participants":["Alex"],"messages":[{"sender":"contact","senderName":"Alex","text":"Hello","timestampLabel":null}],"matchedChatID":null,"matchConfidence":0.9}"#
    }
}
