import Foundation
import XCTest

@testable import FrameReply

final class ProviderPromptContractTests: ProviderAnalysisTestCase {
    func testTaskContractsExposeClosedExpectedSchemas() throws {
        let contracts: [(AIOutputContract, Set<String>, Int)] = [
            (
                ChatImportPrompt.contract(for: makeRequest()),
                [
                    "conversationTitle", "conversationKind", "titleSource",
                    "ownershipConvention", "messages", "matchedChatID", "matchConfidence"
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
                    "conversationTitle", "conversationKind", "titleSource", "messages",
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
            XCTAssertFalse(contract.instructions.contains("Return the JSON object as raw text only."))
            XCTAssertEqual(contract.schema["additionalProperties"] as? Bool, false)
            let properties = try XCTUnwrap(contract.schema["properties"] as? [String: Any])
            XCTAssertEqual(Set(properties.keys), keys)
            XCTAssertEqual(Set(try XCTUnwrap(contract.schema["required"] as? [String])), keys)
        }

        let screenshotText = try schemaText(contracts[0].0.schema)
        let sharedText = try schemaText(contracts[1].0.schema)
        XCTAssertTrue(screenshotText.contains("outerAlignment"))
        XCTAssertFalse(sharedText.contains("outerAlignment"))
        XCTAssertFalse(sharedText.contains("ownershipConvention"))

        let sharedProperties = try XCTUnwrap(
            contracts[1].0.schema["properties"] as? [String: Any]
        )
        let sharedMessages = try XCTUnwrap(sharedProperties["messages"] as? [String: Any])
        XCTAssertEqual(
            sharedMessages["maxItems"] as? Int,
            SharedTranscriptInput.maximumEstimatedMessageCount
        )

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

    func testTextImportPromptIncludesAliasesAsNonConclusiveEvidence() {
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
        XCTAssertTrue(input.contains("Saved importer names (selfAliases):"))
        XCTAssertTrue(input.contains(#"["Alias Alpha"]"#))
        XCTAssertTrue(input.contains(#""participantAliases":["Contact B"]"#))
        XCTAssertTrue(ChatImportPrompt.textImportInstructions.contains("strong evidence"))
        XCTAssertTrue(ChatImportPrompt.textImportInstructions.contains("but not conclusive proof"))
    }

    func testReplyProducingContractsShareGroundedStylePolicy() {
        let standard = SuggestedReplyPrompt.contract(for: .standard, appLanguage: "en")
        let drafting = SuggestedReplyPrompt.contract(for: .drafting, appLanguage: "en")
        let persona = SuggestedReplyPrompt.contract(
            for: .personaStyleLearning,
            appLanguage: "en"
        )

        for instructions in [standard.instructions, drafting.instructions] {
            XCTAssertEqual(instructions.components(separatedBy: "Reply style").count - 1, 1)
            for policy in [
                "Each reply string must contain only the ready-to-send message",
                "Style must not change grounded meaning, uncertainty, or emotional position",
                "Messages from non-user participants remain valid sources for reply content",
                "never treat their vocabulary, dialect, catchphrases, punctuation habits, or identity markers as evidence of the user's voice"
            ] {
                XCTAssertTrue(instructions.contains(policy), policy)
            }
        }
        XCTAssertFalse(persona.instructions.contains("Reply style"))
        XCTAssertTrue(standard.instructions.contains("When personaLearningEnabled is true"))
    }

    func testTaskInputsContainOnlyContractRelevantData() {
        let standard = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .standard))
        for expected in [
            "chatMemories", "personaLearningEnabled\":true",
            "personalInfoLearningEnabled\":true", "recentMessages", "<text_length_limits>"
        ] {
            XCTAssertTrue(standard.contains(expected), expected)
        }
        for excluded in [
            "personaLearningMessages", "personalInfoLearningMessages", "appLanguage",
            "presentationLanguageIdentifier", "\"chatName\"", "\"personaName\""
        ] {
            XCTAssertFalse(standard.contains(excluded), excluded)
        }

        let drafting = SuggestedReplyPrompt.input(for: makeReplyRequest(task: .drafting))
        XCTAssertTrue(drafting.contains("draftingInput"))
        XCTAssertTrue(drafting.contains("personalInfo"))
        XCTAssertFalse(drafting.contains("personalInfoLearningEnabled"))

        let persona = SuggestedReplyPrompt.input(
            for: makeReplyRequest(task: .personaStyleLearning)
        )
        XCTAssertTrue(persona.contains("activeObservations"))
        XCTAssertTrue(persona.contains("recentMessages"))
        XCTAssertFalse(persona.contains("chatMemories"))
        XCTAssertFalse(persona.contains("personalInfo"))
        XCTAssertFalse(persona.contains("draftingInput"))
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
                "Maximum length: 300 Unicode code points"
            )
        )

        let replies = try XCTUnwrap(properties["replies"] as? [String: Any])
        XCTAssertEqual(replies["minItems"] as? Int, 0)
        XCTAssertEqual(replies["maxItems"] as? Int, 2)
        let replyItems = try XCTUnwrap(replies["items"] as? [String: Any])
        XCTAssertNil(replyItems["maxLength"])
        XCTAssertTrue(
            try XCTUnwrap(replyItems["description"] as? String).contains(
                "Maximum length: 500 Unicode code points"
            )
        )
        XCTAssertEqual(try schemaText(contract.schema), canonicalBefore)
    }

    func testContractsResolveAppLanguageWithoutChangingSchemaOrInputShape() throws {
        for task in [
            SuggestedReplyTask.standard, .drafting, .personaStyleLearning
        ] {
            let englishSchema = try schemaText(
                SuggestedReplyPrompt.contract(for: task, appLanguage: "en").schema
            )
            for (identifier, descriptor) in [
                ("en", "English (en)"),
                ("en-US", "English (United States) (en-US)"),
                ("zh-Hans", "Chinese, Simplified (zh-Hans)")
            ] {
                let contract = SuggestedReplyPrompt.contract(
                    for: task,
                    appLanguage: identifier
                )
                XCTAssertEqual(
                    contract.instructions.components(separatedBy: descriptor).count - 1,
                    1,
                    identifier
                )
                XCTAssertEqual(try schemaText(contract.schema), englishSchema, identifier)
            }
        }

        let mixed = makeReplyRequest(
            task: .standard,
            recentMessageText: "晚饭七点？",
            personaLearningText: "当然"
        )
        let input = SuggestedReplyPrompt.input(for: mixed)
        XCTAssertTrue(input.contains("晚饭七点？"))
        XCTAssertFalse(input.contains("appLanguage"))
    }
}
