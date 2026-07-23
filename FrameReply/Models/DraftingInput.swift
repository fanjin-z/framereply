import Foundation

nonisolated enum DraftingInputLimits {
    static let maximumCharacterCount = 500
    static let counterDisplayThreshold = 400

    static func shouldShowCounter(for input: String) -> Bool {
        input.count >= counterDisplayThreshold
    }

    static func canAccept(_ input: String) -> Bool {
        input.count <= maximumCharacterCount
    }

    static func validated(_ input: String?) throws -> String? {
        guard let input else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard canAccept(trimmed) else {
            throw DraftingInputError.tooLong(maximum: maximumCharacterCount)
        }
        return trimmed
    }
}

nonisolated enum DraftingInputError: LocalizedError, Equatable, Sendable {
    case tooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .tooLong(let maximum):
            if maximum == DraftingInputLimits.maximumCharacterCount {
                String(localized: AppStrings.Shortcut.contextTooLong)
            } else {
                "Keep context under \(maximum) characters."
            }
        }
    }
}
