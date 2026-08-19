import SwiftData
import XCTest

@testable import FrameReply

@MainActor
final class LocalizationArchitectureTests: XCTestCase {
    func testChatPresentationKeepsStoredContentAndResolvesMissingFallbacks() {
        let record = ChatRecord(id: "untitled", title: nil, previewText: nil)

        XCTAssertNil(record.title)
        XCTAssertNil(record.previewText)
        XCTAssertEqual(record.displayTitle(locale: Locale(identifier: "en")), "Imported Chat")
        XCTAssertEqual(record.displayPreview(locale: Locale(identifier: "en")), "No messages yet")

        let titled = ChatRecord(
            id: "titled", title: "Equipo Ñ", previewText: "明天见"
        )
        XCTAssertEqual(titled.displayTitle(locale: Locale(identifier: "es")), "Equipo Ñ")
        XCTAssertEqual(titled.displayPreview(locale: Locale(identifier: "zh-Hans")), "明天见")
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

    func testSuccessfulNoReplyPresentationsUseLocalizedResources() {
        let locale = Locale(identifier: "en")

        XCTAssertEqual(
            AppStrings.resolve(AppStrings.Replies.waitSectionMessage, locale: locale),
            "You sent the latest message. No reply is needed yet."
        )
        XCTAssertEqual(
            AppStrings.resolve(
                AppStrings.Replies.waitStrategy(
                    direction: "After they respond, continue with one relevant question."
                ),
                locale: locale
            ),
            "Wait for a response first. After they respond, continue with one relevant question."
        )
        XCTAssertEqual(
            AppStrings.resolve(
                AppStrings.Replies.waitRationale(
                    reason: "Their response determines the useful next step."
                ),
                locale: locale
            ),
            "You sent the latest message, so another message now may be premature. Their response determines the useful next step."
        )
        XCTAssertEqual(
            AppStrings.resolve(AppStrings.Replies.groupPauseSectionMessage, locale: locale),
            "No reply is needed right now. You can wait for a better opening in the group."
        )
        XCTAssertEqual(
            AppStrings.resolve(
                AppStrings.Replies.groupPauseStrategy(
                    direction: "Join when the discussion returns to shared logistics."
                ),
                locale: locale
            ),
            "Wait for a better opening in the group. Join when the discussion returns to shared logistics."
        )
        XCTAssertEqual(
            AppStrings.resolve(
                AppStrings.Replies.groupPauseRationale(
                    reason: "The current request is between two other participants."
                ),
                locale: locale
            ),
            "The latest group turn does not need your response. The current request is between two other participants."
        )
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
