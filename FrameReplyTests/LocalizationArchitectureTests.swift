import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class LocalizationArchitectureTests: XCTestCase {
    func testLegalLinksAlwaysUseCanonicalEnglishDestinations() {
        let documents: [(AppLegalDocument, String)] = [
            (.privacy, "privacy"),
            (.terms, "terms"),
            (.support, "support"),
            (.ageSuitability, "age-suitability")
        ]
        for (document, path) in documents {
            XCTAssertEqual(
                AppLegalLinks.url(for: document).absoluteString,
                "https://fanjin-z.github.io/framereply/\(path)"
            )
        }
    }

    func testBuiltInPersonaKeepsStableIdentityAndPerFieldOverrides() {
        let record = PersonaRecord(builtInID: .professional)

        XCTAssertEqual(record.builtInID, .professional)
        XCTAssertNil(record.nameOverride)
        let definition = BuiltInPersonaDefinition.definition(for: .professional)
        for locale in ["en", "zh-Hans"].map(Locale.init(identifier:)) {
            XCTAssertEqual(
                record.resolvedName(locale: locale), definition.localizedName(locale: locale))
        }
        XCTAssertEqual(
            record.promptInstructions,
            BuiltInPersonaDefinition.definition(for: .professional).canonicalInstructions
        )

        record.name = "My Work Voice"

        XCTAssertEqual(record.nameOverride, "My Work Voice")
        XCTAssertEqual(record.resolvedName(locale: Locale(identifier: "es")), "My Work Voice")
        XCTAssertNil(record.summaryOverride)
    }

    func testBuiltInObservationSeparatesDisplayTemplateFromCanonicalPromptText() {
        let record = PersonaObservationRecord(
            personaID: UUID(),
            text: "",
            templateIDRaw: BuiltInObservationID.concise.rawValue,
            origin: PersonaObservationOrigin.seed.rawValue
        )

        XCTAssertEqual(record.templateID, .concise)
        XCTAssertEqual(record.promptText, BuiltInObservationID.concise.canonicalPromptText)
        XCTAssertFalse(record.localizedText.isEmpty)
        XCTAssertEqual(record.localizedText, BuiltInObservationID.concise.localizedText())
    }

    func testSupportedLanguageResolutionKeepsTraditionalChineseSeparate() {
        let supported = ["en", "zh-Hans"]

        XCTAssertEqual(
            Bundle.preferredLocalizations(
                from: supported,
                forPreferences: ["zh-Hans", "en"]
            ).first,
            "zh-Hans"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(
                from: supported,
                forPreferences: ["zh-Hant", "en"]
            ).first,
            "en"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(
                from: supported,
                forPreferences: ["zh-TW", "en"]
            ).first,
            "en"
        )
        XCTAssertEqual(
            Bundle.preferredLocalizations(
                from: supported,
                forPreferences: ["zh-Hant", "zh-Hans", "en"]
            ).first,
            "zh-Hans"
        )
    }

    func testDictationFollowsAppLanguage() {
        let cases: [(String, GuidanceSpeechLanguage)] = [
            ("zh-Hans", .mandarin),
            ("en", .english)
        ]
        for (appLanguage, expected) in cases {
            XCTAssertEqual(
                GuidanceSpeechLanguage.resolve(appLanguage: appLanguage),
                expected)
        }
    }

    func testReplyCachesAreIsolatedByAppLanguage() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        try repository.saveSuggestedRepliesOnly(
            chatID: "chat",
            appLanguage: "en",
            replies: ["A", "B"],
            conversationStrategy: "English strategy",
            strategyRationale: "English rationale",
            inputFingerprint: "en-fingerprint",
            promptVersion: SuggestedReplyPrompt.version
        )
        try repository.saveSuggestedRepliesOnly(
            chatID: "chat",
            appLanguage: "es",
            replies: ["A", "B"],
            conversationStrategy: "Estrategia",
            strategyRationale: "Explicación",
            inputFingerprint: "es-fingerprint",
            promptVersion: SuggestedReplyPrompt.version
        )

        XCTAssertEqual(
            try repository.suggestedReplyCache(
                chatID: "chat", appLanguage: "en")?.conversationStrategy,
            "English strategy"
        )
        XCTAssertEqual(
            try repository.suggestedReplyCache(
                chatID: "chat", appLanguage: "es")?.conversationStrategy,
            "Estrategia"
        )
        XCTAssertNil(
            try repository.suggestedReplyCache(
                chatID: "chat", appLanguage: "zh-Hans")
        )
    }
}
