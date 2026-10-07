import Foundation

/// Keeps recognition revisions separate from the text that existed before dictation.
nonisolated struct GuidanceDictationDraft {
    let original: String
    private let prefix: String
    private let suffix: String
    private var finalized = ""
    private var provisional = ""

    init(text: String, selection: Range<String.Index>? = nil) {
        original = text
        let range =
            selection.flatMap { Self.validatedSelection($0, in: text) }
            ?? text.endIndex..<text.endIndex
        prefix = String(text[..<range.lowerBound])
        suffix = String(text[range.upperBound...])
    }

    /// Resolve fresh character boundaries instead of subscripting with possibly
    /// stale editor indices. If a selection no longer fits, dictation appends.
    private static func validatedSelection(
        _ selection: Range<String.Index>, in text: String
    ) -> Range<String.Index>? {
        let lower =
            selection.lowerBound == text.endIndex
            ? text.endIndex : text.indices.first { $0 == selection.lowerBound }
        let upper =
            selection.upperBound == text.endIndex
            ? text.endIndex : text.indices.first { $0 == selection.upperBound }
        guard let lower, let upper, lower <= upper else { return nil }
        return lower..<upper
    }

    var text: String {
        let transcript = Self.join(finalized, provisional)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return original }
        return Self.join(Self.join(prefix, transcript), suffix)
    }

    mutating func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized = Self.join(finalized, text)
            provisional = ""
        } else {
            provisional = text
        }
    }

    private static func join(_ left: String, _ right: String) -> String {
        guard let last = left.last, let first = right.first else { return left + right }
        // Apple can deliver phrases without boundary spaces. Add a space between
        // Latin words/numbers, while preserving Chinese and supplied whitespace.
        let needsSpace =
            last.isASCII && first.isASCII
            && (last.isLetter || last.isNumber || ".!?".contains(last))
            && (first.isLetter || first.isNumber)
        return left + (needsSpace ? " " : "") + right
    }
}
