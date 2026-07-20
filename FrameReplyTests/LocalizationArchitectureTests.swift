import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class LocalizationArchitectureTests: XCTestCase {
    func testUntitledChatFallbackIsPresentationOnly() {
        let record = ChatRecord(id: "untitled", title: nil, previewText: nil)

        XCTAssertNil(record.title)
        XCTAssertNil(record.previewText)
        XCTAssertEqual(record.displayTitle(locale: Locale(identifier: "en")), "Imported Chat")
        XCTAssertEqual(record.displayPreview(locale: Locale(identifier: "en")), "No messages yet")
    }

    func testStoredChatPresentationRemainsVerbatim() {
        let record = ChatRecord(
            id: "titled", title: "Equipo Ñ", previewText: "明天见"
        )

        XCTAssertEqual(record.displayTitle(locale: Locale(identifier: "es")), "Equipo Ñ")
        XCTAssertEqual(record.displayPreview(locale: Locale(identifier: "zh-Hans")), "明天见")
    }

    func testMissingChatLookupUsesNonOptionalPresentationFallback() {
        XCTAssertEqual(
            ChatPresentation.title(for: nil, locale: Locale(identifier: "en")),
            "Imported Chat"
        )
    }

    func testTypedInterpolatedResourcePreservesArguments() {
        let value = AppStrings.resolve(
            AppStrings.Chat.mergeCandidate(title: "Project Team", alias: "Alex"),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(value, "Project Team — also Alex")
    }

    func testLegalLinksAlwaysUseCanonicalEnglishDestinations() {
        let documents: [(AppLegalDocument, String)] = [
            (.privacy, "privacy"),
            (.terms, "terms"),
            (.support, "support"),
            (.ageSuitability, "age-suitability")
        ]
        let locales = ["en", "es", "zh-Hans"].map(Locale.init(identifier:))

        for (document, path) in documents {
            let urls = locales.map { _ in AppLegalLinks.url(for: document) }
            XCTAssertEqual(Set(urls).count, 1)
            XCTAssertEqual(
                urls.first?.absoluteString,
                "https://fanjin-z.github.io/framereply/\(path)"
            )
        }
    }

    func testBuiltInPersonaKeepsStableIdentityAndPerFieldOverrides() {
        let record = PersonaRecord(builtInID: .professional)

        XCTAssertEqual(record.builtInID, .professional)
        XCTAssertNil(record.nameOverride)
        XCTAssertEqual(record.resolvedName(locale: Locale(identifier: "en")), "Professional")

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
    }

    func testReplyCachesAreIsolatedByPresentationLanguage() throws {
        let container = try FrameReplyDataStore.makeContainer(inMemory: true)
        let repository = ChatRepository(container: container)

        try repository.saveSuggestedRepliesOnly(
            chatID: "chat",
            presentationLanguageIdentifier: "en",
            replies: ["A", "B"],
            conversationStrategy: "English strategy",
            strategyRationale: "English rationale",
            inputFingerprint: "en-fingerprint",
            promptVersion: SuggestedReplyPrompt.version
        )
        try repository.saveSuggestedRepliesOnly(
            chatID: "chat",
            presentationLanguageIdentifier: "es",
            replies: ["A", "B"],
            conversationStrategy: "Estrategia",
            strategyRationale: "Explicación",
            inputFingerprint: "es-fingerprint",
            promptVersion: SuggestedReplyPrompt.version
        )

        XCTAssertEqual(
            try repository.suggestedReplyCache(
                chatID: "chat", presentationLanguageIdentifier: "en")?.conversationStrategy,
            "English strategy"
        )
        XCTAssertEqual(
            try repository.suggestedReplyCache(
                chatID: "chat", presentationLanguageIdentifier: "es")?.conversationStrategy,
            "Estrategia"
        )
        XCTAssertNil(
            try repository.suggestedReplyCache(
                chatID: "chat", presentationLanguageIdentifier: "zh-Hans")
        )
    }
}
