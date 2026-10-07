import Foundation
import Observation
import Translation

/// Display-only translations, retained for the lifetime of the history sheet.
@MainActor
@Observable
final class ChatHistoryTranslation {
    struct Key: Hashable {
        let messageID: UUID
        let sourceText: String
        let targetLanguageIdentifier: String
    }

    struct Request: Equatable {
        let id = UUID()
        let key: Key
    }

    enum Failure: Equatable {
        case unsupportedLanguage
        case unavailable
        case failed

        var message: LocalizedStringResource {
            switch self {
            case .unsupportedLanguage:
                "This message can't be translated into the app language."
            case .unavailable:
                "Translation isn't available on this device."
            case .failed:
                "Couldn't translate this message. Check your connection if a language download is needed, then try again."
            }
        }
    }

    enum State: Equatable {
        case translating(Request)
        case translated(String)
        case failed(Failure)
    }

    private(set) var states: [Key: State] = [:]
    private var cache: [Key: String] = [:]

    func begin(_ key: Key) -> Request? {
        if case .translating = states[key] { return nil }
        if let text = cache[key] {
            states[key] = .translated(text)
            return nil
        }
        let request = Request(key: key)
        states[key] = .translating(request)
        return request
    }

    func isTranslating(_ request: Request) -> Bool {
        states[request.key] == .translating(request)
    }

    func finish(_ request: Request, text: String) {
        guard isTranslating(request) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(request, reason: .failed)
            return
        }
        cache[request.key] = text
        states[request.key] = .translated(text)
    }

    func fail(_ request: Request, reason: Failure) {
        guard isTranslating(request) else { return }
        states[request.key] = .failed(reason)
    }

    func cancel(_ request: Request) {
        guard isTranslating(request) else { return }
        hide(request.key)
    }

    func hide(_ key: Key) {
        states[key] = nil
    }
}

enum ChatTranslationSupport {
    static func availability() -> LanguageAvailability {
        if #available(iOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .highFidelity)
        }
        return LanguageAvailability()
    }

    static func configuration(target: Locale.Language) -> TranslationSession.Configuration {
        if #available(iOS 26.4, *) {
            return TranslationSession.Configuration(
                target: target, preferredStrategy: .highFidelity)
        }
        return TranslationSession.Configuration(target: target)
    }

    static func languageName(_ identifier: String, locale: Locale) -> String {
        locale.localizedString(forIdentifier: identifier) ?? identifier
    }
}
