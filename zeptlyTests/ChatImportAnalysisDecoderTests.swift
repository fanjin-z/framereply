import Foundation
import XCTest

@testable import zeptly

final class ChatImportAnalysisDecoderTests: XCTestCase {
    func testDecodesExactScreenshotContract() throws {
        let result = try decode(validScreenshotJSON())
        XCTAssertEqual(result.extractionStatus, .ok)
        XCTAssertEqual(result.messages.first?.text, "Hello")
        XCTAssertEqual(result.messages.first?.sender, .otherParticipant)
    }

    func testRejectsInvalidStructuredOutputAndCandidateMatches() throws {
        let exact = validScreenshotJSON()
        assertFailure("```json\n\(exact)\n```", kind: .invalidJSON)
        assertFailure("Here is the result: \(exact)", kind: .invalidJSON)
        assertFailure(
            exact.replacingOccurrences(
                of: "\"conversationTitle\"", with: "\"conversation_title\""),
            kind: .schemaMismatch, path: "root")
        assertFailure(
            exact.replacingOccurrences(
                of: "\"matchConfidence\":0", with: "\"extra\":true,\"matchConfidence\":0"),
            kind: .schemaMismatch, path: "root")
        assertFailure(
            exact.replacingOccurrences(
                of: "\"senderEvidence\":\"alignment_convention\"",
                with: "\"quotedReply\":null,\"senderEvidence\":\"alignment_convention\""),
            kind: .schemaMismatch, path: "messages[0]")
        assertFailure(nil, kind: .emptyResponse)
        assertFailure(
            validScreenshotJSON(), finishReason: "length",
            kind: .truncatedResponse, path: "finish_reason")
        assertFailure("{not json", kind: .invalidJSON)
        assertFailure(
            validScreenshotJSON().replacingOccurrences(
                of: "\"matchedChatID\":null",
                with: "\"matchedChatID\":\"unknown\""),
            kind: .invalidCandidateID, path: "matchedChatID")
        XCTAssertEqual(
            try decode(noMessagesJSON()).extractionStatus,
            .noMessages)
        assertFailure(
            noMessagesJSON().replacingOccurrences(
                of: "\"no_messages\"", with: "\"ok\""),
            kind: .incompleteMessages, path: "messages")
        assertFailure(
            validScreenshotJSON().replacingOccurrences(
                of: "\"ok\"", with: "\"no_messages\""),
            kind: .incompleteMessages, path: "messages")

        assertFailure(
            exact.replacingOccurrences(
                of: "\"matchConfidence\":0", with: "\"matchConfidence\":0.9"),
            kind: .schemaMismatch, path: "matchConfidence")

        let known =
            exact
            .replacingOccurrences(
                of: "\"matchedChatID\":null", with: "\"matchedChatID\":\"known\""
            )
            .replacingOccurrences(
                of: "\"matchConfidence\":0", with: "\"matchConfidence\":0.95")
        XCTAssertNoThrow(try decode(known))
    }

    func testVisualOwnershipNormalizationPreservesSenderSafeguards() throws {
        let contradictory = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"sender\":\"other_participant\"", with: "\"sender\":\"user\""
            )
            .replacingOccurrences(
                of: "\"senderEvidence\":\"alignment_convention\"",
                with: "\"senderEvidence\":\"message_status_indicator\"")
        XCTAssertEqual(try decode(contradictory).messages.first?.sender, .unknown)

        let user = validScreenshotJSON()
            .replacingOccurrences(
                of: "\"sender\":\"other_participant\"", with: "\"sender\":\"user\""
            )
            .replacingOccurrences(
                of: "\"outerAlignment\":\"left\"", with: "\"outerAlignment\":\"right\"")
        XCTAssertEqual(try decode(user).messages.first?.sender, .user)
    }

    func testSharedTranscriptAcceptsOnlyTextContract() throws {
        let result = try ChatImportAnalysisDecoder.decode(
            content: validSharedJSON(), finishReason: "stop",
            isSharedTranscript: true, candidateIDs: [])
        XCTAssertEqual(result.messages.first?.senderName, "Alice")
        XCTAssertEqual(result.ownershipConvention, .unobservable)
        XCTAssertEqual(result.messages.first?.outerAlignment, .unknown)

        assertFailure(
            validSharedJSON().replacingOccurrences(
                of: "\"senderEvidence\":\"author_label\"",
                with: "\"outerAlignment\":\"left\",\"senderEvidence\":\"author_label\""),
            isSharedTranscript: true, kind: .schemaMismatch,
            path: "messages[0]")
    }

    private func decode(_ content: String?, finishReason: String? = "stop") throws
        -> ChatImportAnalysis
    {
        try ChatImportAnalysisDecoder.decode(
            content: content, finishReason: finishReason,
            isSharedTranscript: false, candidateIDs: ["known"])
    }

    private func assertFailure(
        _ content: String?,
        finishReason: String? = "stop",
        isSharedTranscript: Bool = false,
        kind: StructuredOutputFailureKind,
        path: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try ChatImportAnalysisDecoder.decode(
                content: content, finishReason: finishReason,
                isSharedTranscript: isSharedTranscript, candidateIDs: ["known"])
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
        {"extractionStatus":"ok","conversationTitle":"Alex","conversationKind":"direct","titleSource":"header","ownershipConvention":{"mode":"opposed_alignment","screenshotOwnerAlignment":"right","screenshotOwnerAuthorLabel":null},"messages":[{"sender":"other_participant","senderName":"Alex","text":"Hello","timestampLabel":null,"outerAlignment":"left","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention"}],"matchedChatID":null,"matchConfidence":0}
        """
    }

    private func noMessagesJSON() -> String {
        """
        {"extractionStatus":"no_messages","conversationTitle":null,"conversationKind":"unknown","titleSource":"unavailable","ownershipConvention":{"mode":"unobservable","screenshotOwnerAlignment":"unknown","screenshotOwnerAuthorLabel":null},"messages":[],"matchedChatID":null,"matchConfidence":0}
        """
    }

    private func validSharedJSON() -> String {
        """
        {"extractionStatus":"ok","conversationTitle":null,"conversationKind":"unknown","titleSource":"unavailable","messages":[{"sender":"unknown","senderName":"Alice","text":"Hello","timestampLabel":"9:42 PM","senderConfidence":0.5,"senderEvidence":"author_label"}],"matchedChatID":null,"matchConfidence":0}
        """
    }
}
