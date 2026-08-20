import Foundation
import XCTest

@testable import FrameReply

final class ChatImportAnalysisDecoderTests: XCTestCase {
    func testDecodesExactScreenshotContractWithoutRecovery() throws {
        let result = try decodeResult(validScreenshotJSON())
        XCTAssertFalse(result.recovered)
        XCTAssertEqual(result.value.extractionStatus, .ok)
        XCTAssertEqual(result.value.messages.first?.text, "Hello")
        XCTAssertEqual(result.value.messages.first?.sender, .otherParticipant)
    }

    func testRecoversWholeFenceAndOneProseWrappedObject() throws {
        let exact = validScreenshotJSON()
        let fenced = try decodeResult("```json\n\(exact)\n```")
        XCTAssertTrue(fenced.recovered)
        XCTAssertEqual(fenced.value.messages.first?.text, "Hello")

        let wrapped = try decodeResult("Here is the result:\n\(exact)\nDone.")
        XCTAssertTrue(wrapped.recovered)
        XCTAssertEqual(wrapped.value.messages.first?.text, "Hello")

        let singletonArray = try decodeResult("[\(exact)]")
        XCTAssertTrue(singletonArray.recovered)
        XCTAssertEqual(singletonArray.value.messages.first?.text, "Hello")
    }

    func testDefaultsSecondaryMetadataToExplicitUncertainty() throws {
        let result = try decodeResult(#"{"messages":[{"text":" Hello "}]}"#)
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(result.value.extractionStatus, .ok)
        XCTAssertNil(result.value.conversationTitle)
        XCTAssertEqual(result.value.conversationKind, .direct)
        XCTAssertEqual(result.value.conversationKindEvidence, .noGroupEvidence)
        XCTAssertFalse(result.value.hasStrongGroupEvidence)
        XCTAssertEqual(result.value.titleSource, .unavailable)
        XCTAssertEqual(result.value.userIdentification, .unobservable)
        XCTAssertNil(result.value.matchedChatID)
        XCTAssertEqual(result.value.matchConfidence, 0)

        let message = try XCTUnwrap(result.value.messages.first)
        XCTAssertEqual(message.text, "Hello")
        XCTAssertEqual(message.sender, .unknown)
        XCTAssertNil(message.senderName)
        XCTAssertNil(message.timestampLabel)
        XCTAssertEqual(message.outerAlignment, .unknown)
        XCTAssertNil(message.outerAuthorLabel)
        XCTAssertEqual(message.senderConfidence, 0)
        XCTAssertEqual(message.senderEvidence, .insufficient)
    }

    func testInvalidSenderCannotBeRecoveredFromOtherUserIdentificationFields() throws {
        let content = validScreenshotJSON().replacingOccurrences(
            of: "\"sender\":\"other_participant\"",
            with: "\"sender\":42")
        let result = try decodeResult(content)
        let message = try XCTUnwrap(result.value.messages.first)
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(message.sender, .unknown)
        XCTAssertEqual(message.outerAlignment, .unknown)
        XCTAssertEqual(message.senderConfidence, 0)
        XCTAssertEqual(message.senderEvidence, .insufficient)
    }

    func testIgnoresUnknownFieldsAndDerivesStatusFromMessages() throws {
        let content =
            (#"{"extractionStatus":"no_messages","#
            + String(validScreenshotJSON().dropFirst()))
            .replacingOccurrences(
                of: "\"matchConfidence\":0",
                with: "\"extra\":true,\"matchConfidence\":0"
            )
            .replacingOccurrences(
                of: "\"senderEvidence\":\"alignment_convention\"",
                with:
                    "\"quotedReply\":\"ignored\",\"senderEvidence\":\"alignment_convention\"")
        let result = try decodeResult(content)
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(result.value.extractionStatus, .ok)
        XCTAssertEqual(result.value.messages.count, 1)

        let empty = try decodeResult(#"{"messages":[]}"#)
        XCTAssertTrue(empty.recovered)
        XCTAssertEqual(empty.value.extractionStatus, .noMessages)
    }

    func testClearsInvalidCandidateAndConfidence() throws {
        let invalid = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"matchedChatID\":null",
                with: "\"matchedChatID\":\"unknown\""
            )
            .replacingOccurrences(
                of: "\"matchConfidence\":0", with: "\"matchConfidence\":0.95")
        let result = try decodeResult(invalid)
        XCTAssertTrue(result.recovered)
        XCTAssertNil(result.value.matchedChatID)
        XCTAssertEqual(result.value.matchConfidence, 0)

        let known = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"matchedChatID\":null",
                with: "\"matchedChatID\":\"known\""
            )
            .replacingOccurrences(
                of: "\"matchConfidence\":0", with: "\"matchConfidence\":0.95")
        let matched = try decodeResult(known)
        XCTAssertEqual(matched.value.matchedChatID, "known")
        XCTAssertEqual(matched.value.matchConfidence, 0.95)
    }

    func testRejectsMalformedCoreMessagesAndAmbiguousJSON() {
        assertFailure(nil, kind: .emptyResponse)
        assertFailure("{not json", kind: .invalidJSON)
        assertFailure("[]", kind: .schemaMismatch, path: "root")
        assertFailure("[{},{}]", kind: .schemaMismatch, path: "root")
        assertFailure("[1]", kind: .schemaMismatch, path: "root")
        assertFailure(#"{"conversationTitle":"Alex"}"#, kind: .schemaMismatch, path: "messages")
        assertFailure(
            #"{"messages":[{"text":42}]}"#,
            kind: .schemaMismatch,
            path: "messages[0].text")
        assertFailure(
            #"{"messages":[{"text":"   "}]}"#,
            kind: .incompleteMessages,
            path: "messages[0].text")
        assertFailure(
            #"First {"messages":[]} second {"messages":[]}"#,
            kind: .invalidJSON)
        assertFailure(
            validScreenshotJSON(),
            finishReason: "length",
            kind: .truncatedResponse,
            path: "finish_reason")
    }

    func testVisualUserIdentificationPreservesSenderSafeguards() throws {
        let contradictory = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"sender\":\"other_participant\"",
                with: "\"sender\":\"user\""
            )
            .replacingOccurrences(
                of: "\"senderEvidence\":\"alignment_convention\"",
                with: "\"senderEvidence\":\"message_status_indicator\"")
        XCTAssertEqual(try decodeResult(contradictory).value.messages.first?.sender, .unknown)

        let user = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"sender\":\"other_participant\"",
                with: "\"sender\":\"user\""
            )
            .replacingOccurrences(
                of: "\"outerAlignment\":\"left\"", with: "\"outerAlignment\":\"right\"")
        XCTAssertEqual(try decodeResult(user).value.messages.first?.sender, .user)
    }

    func testTwoNamedAuthorsOppositeUserAlignmentEstablishGroupWithoutVisibleUser() throws {
        let content = """
            {"conversationTitle":null,"conversationKindEvidence":"two_or_more_named_authors_opposite_user_alignment","titleSource":"unavailable","userIdentification":{"mode":"opposed_alignment","userAlignment":"right","userAuthorLabel":null},"messages":[{"sender":"group_participant","senderName":"Alice","text":"First","timestampLabel":null,"outerAlignment":"left","outerAuthorLabel":"Alice","senderConfidence":0.9,"senderEvidence":"alignment_convention"},{"sender":"group_participant","senderName":"Bob","text":"Second","timestampLabel":null,"outerAlignment":"left","outerAuthorLabel":"Bob","senderConfidence":0.9,"senderEvidence":"alignment_convention"}],"matchedChatID":null,"matchConfidence":0}
            """

        let result = try decodeResult(content)

        XCTAssertEqual(result.value.conversationKind, .group)
        XCTAssertEqual(
            result.value.conversationKindEvidence,
            .twoOrMoreNamedAuthorsOppositeUserAlignment)
        XCTAssertTrue(result.value.hasStrongGroupEvidence)
        XCTAssertFalse(result.value.messages.contains { $0.sender == .user })

        let sameSideContent = content.replacingOccurrences(
            of: #""outerAlignment":"left""#,
            with: #""outerAlignment":"right""#)
        let sameSideResult = try decodeResult(sameSideContent)
        XCTAssertEqual(sameSideResult.value.conversationKind, .direct)
        XCTAssertFalse(sameSideResult.value.hasStrongGroupEvidence)
    }

    func testSharedTranscriptIgnoresVisualMetadataWithoutIdentifyingUser() throws {
        let content = validSharedJSON().replacingOccurrences(
            of: "\"senderEvidence\":\"author_label\"",
            with: "\"outerAlignment\":\"left\",\"senderEvidence\":\"author_label\"")
        let result = try ChatImportAnalysisDecoder.decodeResult(
            content: content,
            finishReason: "stop",
            isSharedTranscript: true,
            candidateIDs: [])
        XCTAssertTrue(result.recovered)
        XCTAssertEqual(result.value.messages.first?.senderName, "Alice")
        XCTAssertEqual(result.value.userIdentification, .unobservable)
        XCTAssertEqual(result.value.messages.first?.outerAlignment, .unknown)
    }

    func testSharedTranscriptRejectsMoreThanMaximumMessages() throws {
        let maximum = SharedTranscriptInput.maximumEstimatedMessageCount
        let accepted = try sharedTranscriptJSON(messageCount: maximum)
        let acceptedResult = try ChatImportAnalysisDecoder.decodeResult(
            content: accepted,
            finishReason: "stop",
            isSharedTranscript: true,
            candidateIDs: []
        )
        XCTAssertEqual(acceptedResult.value.messages.count, maximum)

        let rejected = try sharedTranscriptJSON(messageCount: maximum + 1)
        XCTAssertThrowsError(
            try ChatImportAnalysisDecoder.decodeResult(
                content: rejected,
                finishReason: "stop",
                isSharedTranscript: true,
                candidateIDs: []
            )
        ) { error in
            XCTAssertEqual(
                error as? StructuredOutputFailure,
                StructuredOutputFailure(kind: .schemaMismatch, codingPath: "messages")
            )
        }
    }

    func testAmbiguousSharedFragmentsDefaultToDirect() throws {
        for authorNames in [["Alice"], ["Alice", "Bob"]] {
            let result = try decodeSharedResult(sharedTranscriptJSON(authors: authorNames))

            XCTAssertEqual(result.value.conversationKind, .direct)
            XCTAssertTrue(result.value.isInferenceOnlyGroupSuggestion)
            XCTAssertFalse(result.value.hasStrongGroupEvidence)
        }
    }

    private func decodeResult(_ content: String?, finishReason: String? = "stop") throws
        -> StructuredOutputDecodingResult<ChatImportAnalysis>
    {
        try ChatImportAnalysisDecoder.decodeResult(
            content: content,
            finishReason: finishReason,
            isSharedTranscript: false,
            candidateIDs: ["known"])
    }

    private func decodeSharedResult(_ content: String) throws
        -> StructuredOutputDecodingResult<ChatImportAnalysis>
    {
        try ChatImportAnalysisDecoder.decodeResult(
            content: content,
            finishReason: "stop",
            isSharedTranscript: true,
            candidateIDs: []
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
            _ = try decodeResult(content, finishReason: finishReason)
            XCTFail("Expected \(kind)", file: file, line: line)
        } catch let failure as StructuredOutputFailure {
            XCTAssertEqual(failure.kind, kind, file: file, line: line)
            XCTAssertEqual(failure.codingPath, path, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func validScreenshotJSON() -> String {
        """
        {"conversationTitle":"Alex","conversationKindEvidence":"no_group_evidence","titleSource":"header","userIdentification":{"mode":"opposed_alignment","userAlignment":"right","userAuthorLabel":null},"messages":[{"sender":"other_participant","senderName":"Alex","text":"Hello","timestampLabel":null,"outerAlignment":"left","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention"}],"matchedChatID":null,"matchConfidence":0}
        """
    }

    private func validSharedJSON() -> String {
        """
        {"conversationTitle":null,"conversationKindEvidence":"no_group_evidence","titleSource":"unavailable","messages":[{"sender":"unknown","senderName":"Alice","text":"Hello","timestampLabel":"9:42 PM","senderConfidence":0.5,"senderEvidence":"author_label"}],"matchedChatID":null,"matchConfidence":0}
        """
    }

    private func sharedTranscriptJSON(messageCount: Int) throws -> String {
        let message: [String: Any] = [
            "sender": "unknown",
            "senderName": "Alice",
            "text": "Hello",
            "timestampLabel": NSNull(),
            "senderConfidence": 0.5,
            "senderEvidence": "author_label"
        ]
        let object: [String: Any] = [
            "conversationTitle": NSNull(),
            "conversationKindEvidence": "no_group_evidence",
            "titleSource": "unavailable",
            "messages": Array(repeating: message, count: messageCount),
            "matchedChatID": NSNull(),
            "matchConfidence": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func sharedTranscriptJSON(authors: [String]) throws -> String {
        let messages = authors.enumerated().map { index, author in
            [
                "sender": "unknown", "senderName": author, "text": "Message \(index)",
                "timestampLabel": "10:0\(index)", "senderConfidence": 0.8,
                "senderEvidence": "author_label"
            ] as [String: Any]
        }
        let object: [String: Any] = [
            "conversationTitle": NSNull(),
            "conversationKindEvidence": "three_or_more_named_message_authors",
            "titleSource": "unavailable",
            "messages": messages,
            "matchedChatID": NSNull(),
            "matchConfidence": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

}
