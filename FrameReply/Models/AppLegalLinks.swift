import Foundation

nonisolated enum AppLegalDocument: String, Sendable {
    case privacy
    case terms
    case support
    case ageSuitability = "age-suitability"
}

nonisolated enum AppLegalLinks {
    /// Returns the canonical, reviewed English document.
    ///
    /// Legal and support pages intentionally do not vary with the app locale. Add a
    /// localized destination only after qualified legal and translation review.
    static func url(for document: AppLegalDocument) -> URL {
        return URL(string: "https://fanjin-z.github.io/framereply/\(document.rawValue)")!
    }
}
