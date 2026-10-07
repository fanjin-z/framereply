import Foundation
import XCTest

@testable import FrameReply

final class ProviderPromptContractTests: ProviderAnalysisTestCase {
    func testTaskContractsExposeClosedExpectedSchemas() throws {
        let contracts: [(AIOutputContract, Set<String>, Int)] = [
            (
                ChatImportPrompt.contract(for: makeRequest()),
                [
                    "conversationTitle", "titleSource", "conversationKindEvidence",
                    "userIdentification", "messages", "matchedChatID", "matchConfidence"
                ],
                ChatImportPrompt.screenshotImportVersion
            ),
            (
                ChatImportPrompt.contract(
                    for: ChatImportAnalysisRequest(
                        transcriptItems: ["Alice: Hi"], candidates: []
                    )
                ),
                [
                    "conversationTitle", "conversationKindEvidence", "titleSource", "messages",
                    "matchedChatID", "matchConfidence"
                ],
                ChatImportPrompt.textImportVersion
            ),
            (
                SuggestedReplyPrompt.contract(for: .standard, appLanguage: "en"),
                [
                    "historySummary", "replies", "conversationStrategy", "strategyRationale",
                    "memoryChanges", "personaObservationChanges", "personalInfoChanges"
                ],
                SuggestedReplyPrompt.version
            ),
            (
                SuggestedReplyPrompt.contract(for: .drafting, appLanguage: "en"),
                ["replies", "conversationStrategy", "strategyRationale"],
                SuggestedReplyPrompt.version
            ),
            (
                SuggestedReplyPrompt.contract(for: .personaStyleLearning, appLanguage: "en"),
                ["personaObservationChanges"],
                SuggestedReplyPrompt.version
            )
        ]

        for (contract, keys, version) in contracts {
            XCTAssertEqual(contract.version, version)
            XCTAssertEqual(contract.schema["additionalProperties"] as? Bool, false)
            let properties = try XCTUnwrap(contract.schema["properties"] as? [String: Any])
            XCTAssertEqual(Set(properties.keys), keys)
            XCTAssertEqual(Set(try XCTUnwrap(contract.schema["required"] as? [String])), keys)
        }

        let screenshotProperties = try XCTUnwrap(
            contracts[0].0.schema["properties"] as? [String: Any]
        )
        let screenshotMessages = try XCTUnwrap(
            screenshotProperties["messages"] as? [String: Any]
        )
        let screenshotMessageItems = try XCTUnwrap(
            screenshotMessages["items"] as? [String: Any]
        )
        let screenshotMessageProperties = try XCTUnwrap(
            screenshotMessageItems["properties"] as? [String: Any]
        )
        XCTAssertNotNil(screenshotMessageProperties["outerAlignment"])
        let userIdentification = try XCTUnwrap(
            screenshotProperties["userIdentification"] as? [String: Any]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(userIdentification["required"] as? [String])),
            ["mode", "userAlignment", "userAuthorLabel"]
        )
        let conversationKindEvidence = try XCTUnwrap(
            screenshotProperties["conversationKindEvidence"] as? [String: Any]
        )
        XCTAssertTrue(
            try XCTUnwrap(conversationKindEvidence["enum"] as? [String]).contains(
                "two_or_more_named_authors_opposite_user_alignment"
            )
        )

        let sharedProperties = try XCTUnwrap(
            contracts[1].0.schema["properties"] as? [String: Any]
        )
        let sharedMessages = try XCTUnwrap(sharedProperties["messages"] as? [String: Any])
        XCTAssertEqual(
            sharedMessages["maxItems"] as? Int,
            SharedTranscriptInput.maximumEstimatedMessageCount
        )
        let sharedMessageItems = try XCTUnwrap(sharedMessages["items"] as? [String: Any])
        let sharedMessageProperties = try XCTUnwrap(
            sharedMessageItems["properties"] as? [String: Any]
        )
        XCTAssertNil(sharedMessageProperties["outerAlignment"])

        let standardProperties = try XCTUnwrap(
            contracts[2].0.schema["properties"] as? [String: Any]
        )
        XCTAssertEqual(
            (standardProperties["memoryChanges"] as? [String: Any])?["maxItems"] as? Int,
            8
        )
        XCTAssertEqual(
            (standardProperties["personalInfoChanges"] as? [String: Any])?["maxItems"] as? Int,
            PersonalInfoLimits.maximumChangesPerGeneration
        )
    }

    func testTextImportInputIncludesAliasesAndCandidates() throws {
        let request = ChatImportAnalysisRequest(
            transcriptItems: [
                "Alias Alpha: Could we move the meeting?",
                "Contact Beta: Tomorrow works for me."
            ],
            candidates: [
                ChatMatchCandidate(
                    id: "contact-beta",
                    title: "Contact Beta",
                    participantAliases: ["Contact B"],
                    recentMessages: []
                )
            ],
            selfAliases: ["Alias Alpha"]
        )

        let input = ChatImportPrompt.input(for: request)
        let arrays = jsonArrays(in: input)
        XCTAssertTrue(arrays.contains { ($0 as? [String]) == request.selfAliases })
        let candidates = arrays.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }
        let candidate = try XCTUnwrap(
            candidates.first { $0["id"] as? String == request.candidates[0].id }
        )
        XCTAssertEqual(
            candidate["participantAliases"] as? [String], request.candidates[0].participantAliases
        )
    }

    func testTaskInputsContainOnlyContractRelevantData() throws {
        let standard = try conversationPayload(
            from: SuggestedReplyPrompt.input(for: makeReplyRequest(task: .standard))
        )
        XCTAssertNotNil(standard["chatMemories"])
        XCTAssertEqual(standard["personaLearningEnabled"] as? Bool, true)
        XCTAssertEqual(standard["personalInfoLearningEnabled"] as? Bool, true)
        XCTAssertNotNil(standard["recentMessages"])
        for excluded in [
            "personaLearningMessages", "personalInfoLearningMessages", "appLanguage",
            "presentationLanguageIdentifier", "chatName", "personaName", "userAliases"
        ] {
            XCTAssertNil(standard[excluded], excluded)
        }

        let drafting = try conversationPayload(
            from: SuggestedReplyPrompt.input(for: makeReplyRequest(task: .drafting))
        )
        XCTAssertNotNil(drafting["draftingInput"])
        XCTAssertNotNil(drafting["personalInfo"])
        XCTAssertNil(drafting["personalInfoLearningEnabled"])

        let persona = try conversationPayload(
            from: SuggestedReplyPrompt.input(
                for: makeReplyRequest(task: .personaStyleLearning)
            )
        )
        let personaContext = try XCTUnwrap(persona["persona"] as? [String: Any])
        XCTAssertNotNil(personaContext["activeObservations"])
        XCTAssertNotNil(persona["recentMessages"])
        XCTAssertNil(persona["chatMemories"])
        XCTAssertNil(persona["personalInfo"])
        XCTAssertNil(persona["draftingInput"])
    }

    func testProviderSchemaMovesOnlyTextLengthsIntoDescriptions() throws {
        let contract = SuggestedReplyPrompt.contract(for: .standard, appLanguage: "en")
        let canonicalBefore = try schemaText(contract.schema)
        let properties = try XCTUnwrap(
            contract.providerSchema["properties"] as? [String: Any]
        )

        let strategy = try XCTUnwrap(properties["conversationStrategy"] as? [String: Any])
        XCTAssertNil(strategy["minLength"])
        XCTAssertNil(strategy["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(strategy["description"] as? String).contains(
                String(SuggestedReplyTextLimits.conversationStrategyMaximumCodePoints)
            ))

        let replies = try XCTUnwrap(properties["replies"] as? [String: Any])
        XCTAssertEqual(replies["minItems"] as? Int, 0)
        XCTAssertEqual(replies["maxItems"] as? Int, 2)
        let replyItems = try XCTUnwrap(replies["items"] as? [String: Any])
        XCTAssertNil(replyItems["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(replyItems["description"] as? String).contains("500")
        )
        XCTAssertEqual(try schemaText(contract.schema), canonicalBefore)
    }

    func testAppLanguageKeepsSchemaAndInputShapeStable() throws {
        let identifiers = ["en", "en-US", "zh-Hans"]
        for task in [
            SuggestedReplyTask.standard, .drafting, .personaStyleLearning
        ] {
            let contracts = identifiers.map {
                SuggestedReplyPrompt.contract(for: task, appLanguage: $0)
            }
            let englishSchema = try schemaText(contracts[0].schema)
            for (identifier, contract) in zip(identifiers, contracts) {
                XCTAssertEqual(try schemaText(contract.schema), englishSchema, identifier)
            }
        }

        let mixed = makeReplyRequest(
            task: .standard,
            recentMessageText: "晚饭七点？",
            personaLearningText: "当然"
        )
        let input = try conversationPayload(from: SuggestedReplyPrompt.input(for: mixed))
        let recentMessages = try XCTUnwrap(input["recentMessages"] as? [[String: Any]])
        XCTAssertTrue(recentMessages.contains { $0["text"] as? String == "晚饭七点？" })
        XCTAssertNil(input["appLanguage"])
    }

    private func jsonArrays(in input: String) -> [[Any]] {
        // Decode complete arrays without depending on prompt prose or JSON whitespace.
        input.indices.filter { input[$0] == "[" }.compactMap { start in
            input.indices.lazy.filter { $0 > start && input[$0] == "]" }.compactMap { end in
                (try? JSONSerialization.jsonObject(with: Data(input[start...end].utf8))) as? [Any]
            }.first
        }
    }

    private func conversationPayload(from input: String) throws -> [String: Any] {
        let startMarker = "<conversation_data>\n"
        let endMarker = "\n</conversation_data>"
        let start = try XCTUnwrap(input.range(of: startMarker)?.upperBound)
        let end = try XCTUnwrap(
            input.range(of: endMarker, range: start..<input.endIndex)?.lowerBound
        )
        let data = try XCTUnwrap(String(input[start..<end]).data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
