import Foundation

/// The language used for FrameReply-owned presentation text.
///
/// Keep this value explicit at boundaries that run outside SwiftUI (AI workflows,
/// App Intents, and response builders). Imported and user-authored content does
/// not use this context and must remain verbatim.
nonisolated struct LocalizationContext: Equatable, Sendable {
    let languageIdentifier: String
    let locale: Locale

    init(languageIdentifier: String, locale: Locale? = nil) {
        self.languageIdentifier = languageIdentifier
        self.locale = locale ?? Locale(identifier: languageIdentifier)
    }

    init(locale: Locale, bundle: Bundle = .main) {
        let supported = bundle.localizations.filter { $0 != "Base" }
        let preferred = Bundle.preferredLocalizations(
            from: supported,
            forPreferences: [locale.identifier]
        ).first
        let fallback = bundle.developmentLocalization ?? "en"
        let identifier = preferred ?? fallback
        self.init(languageIdentifier: identifier, locale: Locale(identifier: identifier))
    }

    static var current: LocalizationContext {
        LocalizationContext(locale: .current)
    }
}
