import Foundation
import XCTest

@testable import zeptly

final class ChatImportAnalysisDecoderTests: XCTestCase {
    func testDecodesExactAndFencedJSON() throws {
        let exact = validJSON()
        XCTAssertEqual(try decode(exact).messages.first?.text, "Hello")
        XCTAssertEqual(try decode("\u{FEFF}  ```json\n\(exact)\n```  ").messages.first?.text, "Hello")
    }

    func testClassifiesInvalidResponses() {
        let missingMessages = validJSON().replacingOccurrences(
            of: #""messages""#,
            with: #""missingMessages""#
        )
        let wrongSender = validJSON().replacingOccurrences(
            of: #""sender":"contact""#,
            with: #""sender":42"#
        )
        let unknownCandidate = validJSON().replacingOccurrences(
            of: #""matchedChatID":null"#,
            with: #""matchedChatID":"unknown""#
        )
        let incompleteMessage = validJSON().replacingOccurrences(
            of: #""text":"Hello""#,
            with: #""text":"   ""#
        )
        let cases: [(String?, String?, StructuredOutputFailureKind, String?)] = [
            (nil, "stop", .emptyResponse, nil),
            (validJSON(), "length", .truncatedResponse, nil),
            ("{not json", "stop", .invalidJSON, nil),
            (missingMessages, "stop", .schemaMismatch, "messages"),
            (wrongSender, "stop", .schemaMismatch, "messages[0].sender"),
            (unknownCandidate, "stop", .invalidCandidateID, "matchedChatID"),
            (incompleteMessage, "stop", .incompleteMessages, "messages")
        ]

        for (content, finishReason, kind, path) in cases {
            assertFailure(content, finishReason: finishReason, kind: kind, path: path)
        }
    }

    func testDecodesLegacyAndUnknownIdentityMetadataConservatively() throws {
        let legacyJSON =
            #"{"conversationTitle":"Alex","messages":[{"sender":"contact","senderName":"Alex","text":"Hello","timestampLabel":null}]}"#
        let legacy = try decode(legacyJSON)

        XCTAssertNil(legacy.sourceApp)
        XCTAssertTrue(legacy.participants.isEmpty)
        XCTAssertNil(legacy.matchedChatID)
        XCTAssertEqual(legacy.matchConfidence, 0)
        XCTAssertEqual(legacy.conversationKind, .unknown)
        XCTAssertEqual(legacy.titleSource, .unavailable)
        XCTAssertNil(legacy.avatarBounds)
        XCTAssertEqual(legacy.matchBasis, .insufficientEvidence)

        let unknownMetadataJSON = validJSON()
            .replacingOccurrences(of: #""conversationKind":"direct""#, with: #""conversationKind":"one_to_one""#)
            .replacingOccurrences(of: #""titleSource":"header""#, with: #""titleSource":"guessed""#)
            .replacingOccurrences(of: #""matchBasis":"display_name""#, with: #""matchBasis":"message_overlap""#)
        let unknownMetadata = try decode(unknownMetadataJSON)

        XCTAssertEqual(unknownMetadata.messages.first?.text, "Hello")
        XCTAssertEqual(unknownMetadata.conversationKind, .unknown)
        XCTAssertEqual(unknownMetadata.titleSource, .unavailable)
        XCTAssertEqual(unknownMetadata.matchBasis, .insufficientEvidence)
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
        #"{"conversationTitle":"Alex","participants":["Alex"],"sourceApp":"Telegram","conversationKind":"direct","titleSource":"header","avatarBounds":null,"messages":[{"sender":"contact","senderName":"Alex","text":"Hello","timestampLabel":null}],"matchedChatID":null,"matchConfidence":0.9,"matchBasis":"display_name"}"#
    }
}
