//
//  TranscriptFingerprinter.swift
//  zeptly
//

import CryptoKit
import Foundation

enum TranscriptFingerprinter {
    static func fingerprint(chatID: String, messages: [MergeMessage]) -> String {
        let transcript = ([chatID] + messages.map { message in
            [
                message.senderKind,
                ChatImportMatcher.normalizedTimestamp(message.timeLabel),
                message.normalizedText
            ].joined(separator: "\u{1F}")
        }).joined(separator: "\u{1E}")

        return SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
