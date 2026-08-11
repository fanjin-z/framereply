import Foundation
import XCTest

@testable import FrameReply

final class SuggestedReplyResultDecoderTests: ProviderAnalysisTestCase {
    func testRecoversOptionalAnalysisFieldsAndPreservesCoreReplies() throws {
        let content = jsonString([
            "historySummary": 42,
            "replies": [" First ", " Second "],
            "conversationStrategy": " Continue after they respond. ",
            "strategyRationale": " The response determines the next step. ",
            "memoryChanges": "invalid",
            "extra": true
        ])
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: "Result:\n\(content)",
            finishReason: "stop",
            task: .standard
        )

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.replies, ["First", "Second"])
        XCTAssertNil(decoded.value.historySummary)
        XCTAssertEqual(decoded.value.conversationStrategy, "Continue after they respond.")
        XCTAssertEqual(decoded.value.strategyRationale, "The response determines the next step.")
        XCTAssertTrue(decoded.value.memoryChanges.isEmpty)
        XCTAssertTrue(decoded.value.personaObservationChanges.isEmpty)
        XCTAssertFalse(decoded.value.personaObservationChangesAvailable)
        XCTAssertTrue(decoded.value.personalInfoChanges.isEmpty)
    }

    func testValidatesPersonalInfoChanges() throws {
        let evidenceID = UUID()
        let accepted = String(repeating: "a", count: 120)
        let rejected = String(repeating: "b", count: 121)
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "historySummary": NSNull(),
                "replies": ["First", "Second"],
                "conversationStrategy": "Answer directly.",
                "strategyRationale": "The current question calls for a direct answer.",
                "memoryChanges": [],
                "personaObservationChanges": [],
                "personalInfoChanges": [
                    [
                        "action": "add", "targetFactID": NSNull(), "text": accepted,
                        "evidenceMessageIDs": [evidenceID.uuidString]
                    ],
                    [
                        "action": "add", "targetFactID": NSNull(), "text": rejected,
                        "evidenceMessageIDs": [evidenceID.uuidString]
                    ],
                    [
                        "action": "archive", "targetFactID": UUID().uuidString,
                        "text": NSNull(),
                        "evidenceMessageIDs": [evidenceID.uuidString, evidenceID.uuidString]
                    ]
                ]
            ]),
            finishReason: "stop",
            task: .standard
        )

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.personalInfoChanges.map(\.text), [accepted])
        XCTAssertEqual(
            decoded.fieldRecoveries,
            [
                StructuredOutputFieldRecovery(
                    path: "personalInfoChanges[1].text",
                    originalCodePointCount: 121,
                    finalCodePointCount: 0
                )
            ]
        )
    }

    func testHandlesSummaryReplyCardinalityAndJSONWrappersConservatively() throws {
        let valid = validStandardRepliesJSON(historySummary: " Merged summary ")
        XCTAssertEqual(
            try SuggestedReplyResultDecoder.decode(
                content: valid, finishReason: "stop", task: .standard
            ).historySummary,
            "Merged summary"
        )
        XCTAssertTrue(
            try SuggestedReplyResultDecoder.decodeResult(
                content: "```json\n\(valid)\n```",
                finishReason: "stop",
                task: .standard
            ).recovered
        )

        for invalidSummary: Any in [NSNull(), 42, "", String(repeating: "x", count: 2_001)] {
            XCTAssertNil(
                try SuggestedReplyResultDecoder.decode(
                    content: validStandardRepliesJSON(historySummary: invalidSummary),
                    finishReason: "stop",
                    task: .standard
                ).historySummary
            )
        }
        for invalidReplies: [Any] in [
            ["only one"], ["same", " same "], ["one", "two", "three"]
        ] {
            XCTAssertThrowsError(
                try SuggestedReplyResultDecoder.decode(
                    content: jsonString([
                        "historySummary": NSNull(),
                        "replies": invalidReplies,
                        "conversationStrategy": "Continue.",
                        "strategyRationale": "The context supports continuing.",
                        "memoryChanges": [],
                        "personaObservationChanges": [],
                        "personalInfoChanges": []
                    ]),
                    finishReason: "stop",
                    task: .standard
                )
            )
        }
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: "\(valid)\n\(valid)",
                finishReason: "stop",
                task: .standard
            )
        )
    }

    func testShortensOverlongTextAtSafeUnicodeBoundaries() throws {
        let exactRationale = String(repeating: "界", count: 448) + "e\u{301}"
        let exact = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": String(repeating: "s", count: 300),
                "strategyRationale": exactRationale
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertFalse(exact.recovered)
        XCTAssertEqual(exact.value.strategyRationale, exactRationale)

        let overlongCombining = String(repeating: "界", count: 449) + "e\u{301}"
        let combining = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": overlongCombining
            ]),
            finishReason: "stop",
            task: .drafting
        )
        XCTAssertEqual(combining.value.strategyRationale, String(repeating: "界", count: 449))
        XCTAssertEqual(combining.fieldRecoveries.first?.originalCodePointCount, 451)

        let completeSentence = String(repeating: "a", count: 430) + "."
        let sentence = try decodeDraftingRationale(
            completeSentence + " " + String(repeating: "b", count: 100)
        )
        XCTAssertEqual(sentence, completeSentence)

        let word = try decodeDraftingRationale(String(repeating: "evidence ", count: 100))
        XCTAssertTrue(word.hasSuffix("…"))
        XCTAssertLessThanOrEqual(
            word.unicodeScalars.count,
            SuggestedReplyTextLimits.strategyRationaleMaximumCodePoints
        )

        let family = "👨‍👩‍👧‍👦"
        let emoji = try decodeDraftingRationale(String(repeating: "x", count: 449) + family)
        XCTAssertEqual(emoji, String(repeating: "x", count: 449))
        XCTAssertFalse(emoji.contains("👨"))

        let cjkSentence = String(repeating: "证", count: 400) + "。"
        XCTAssertEqual(
            try decodeDraftingRationale(cjkSentence + String(repeating: "据", count: 100)),
            cjkSentence
        )
    }

    func testRejectsMissingEmptyAndWrongTypeStrategyFields() throws {
        for rationale: Any in [NSNull(), "", 42] {
            XCTAssertThrowsError(
                try SuggestedReplyResultDecoder.decode(
                    content: jsonString([
                        "replies": [],
                        "conversationStrategy": "Continue after a response.",
                        "strategyRationale": rationale
                    ]),
                    finishReason: "stop",
                    task: .drafting
                )
            )
        }
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: jsonString([
                    "replies": [],
                    "strategyRationale": "The latest message determines the next step."
                ]),
                finishReason: "stop",
                task: .drafting
            )
        )
    }

    func testRetainsOnlyValidLearningChanges() throws {
        let memoryEvidence = UUID()
        let personaEvidence = [UUID(), UUID()]
        let personalInfoEvidence = UUID()
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "historySummary": NSNull(),
                "replies": ["First", "Second"],
                "conversationStrategy": "Continue",
                "strategyRationale": "The latest message supports a direct answer.",
                "memoryChanges": [
                    [
                        "action": "add", "targetMemoryID": NSNull(), "text": "Likes tea",
                        "evidenceMessageIDs": [memoryEvidence.uuidString]
                    ],
                    ["action": "add", "targetMemoryID": NSNull(), "text": 42]
                ],
                "personaObservationChanges": [
                    [
                        "action": "add", "targetObservationID": NSNull(),
                        "text": "Uses short sentences",
                        "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                    ],
                    ["action": "invented"]
                ],
                "personalInfoChanges": [
                    [
                        "action": "add", "targetFactID": NSNull(),
                        "text": "Prefers window seats",
                        "evidenceMessageIDs": [personalInfoEvidence.uuidString]
                    ]
                ]
            ]),
            finishReason: "stop",
            task: .standard
        )

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.memoryChanges.count, 1)
        XCTAssertEqual(decoded.value.personaObservationChanges.count, 1)
        XCTAssertTrue(decoded.value.personaObservationChangesAvailable)
        XCTAssertEqual(decoded.value.personalInfoChanges.count, 1)
        XCTAssertThrowsError(
            try SuggestedReplyResultDecoder.decode(
                content: "{}", finishReason: "stop", task: .personaStyleLearning
            )
        )
    }

    func testUsesSeparateMemoryAndObservationTextLimits() throws {
        let memoryEvidence = UUID()
        let personaEvidence = [UUID(), UUID()]
        let acceptedMemory = String(repeating: "界", count: 118) + "e\u{301}"
        let rejectedMemory = String(repeating: "界", count: 119) + "e\u{301}"
        let acceptedObservation = String(repeating: "界", count: 240)
        let rejectedObservation = String(repeating: "o", count: 239) + "👨‍👩‍👧‍👦"
        let decoded = try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "historySummary": NSNull(),
                "replies": ["First", "Second"],
                "conversationStrategy": "Continue",
                "strategyRationale": "The latest message supports a direct answer.",
                "memoryChanges": [
                    [
                        "action": "add", "targetMemoryID": NSNull(), "text": acceptedMemory,
                        "evidenceMessageIDs": [memoryEvidence.uuidString]
                    ],
                    [
                        "action": "update", "targetMemoryID": UUID().uuidString,
                        "text": rejectedMemory,
                        "evidenceMessageIDs": [memoryEvidence.uuidString]
                    ]
                ],
                "personaObservationChanges": [
                    [
                        "action": "add", "targetObservationID": NSNull(),
                        "text": acceptedObservation,
                        "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                    ],
                    [
                        "action": "add", "targetObservationID": NSNull(),
                        "text": rejectedObservation,
                        "evidenceMessageIDs": personaEvidence.map(\.uuidString)
                    ]
                ],
                "personalInfoChanges": []
            ]),
            finishReason: "stop",
            task: .standard
        )

        XCTAssertTrue(decoded.recovered)
        XCTAssertEqual(decoded.value.memoryChanges.map(\.text), [acceptedMemory])
        XCTAssertEqual(decoded.value.personaObservationChanges.map(\.text), [acceptedObservation])
        XCTAssertEqual(
            decoded.fieldRecoveries.map(\.path),
            ["memoryChanges[1].text", "personaObservationChanges[1].text"]
        )
    }

    private func decodeDraftingRationale(_ rationale: String) throws -> String {
        try SuggestedReplyResultDecoder.decodeResult(
            content: jsonString([
                "replies": [],
                "conversationStrategy": "Continue after a response.",
                "strategyRationale": rationale
            ]),
            finishReason: "stop",
            task: .drafting
        ).value.strategyRationale
    }
}
