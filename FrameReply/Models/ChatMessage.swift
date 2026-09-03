//
//  ChatMessage.swift
//  FrameReply
//

import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Sender: Equatable {
        case otherParticipant
        case user
        case groupParticipant(String)
        case unknown
    }

    let id: UUID
    let sender: Sender
    let text: String
    let timeLabel: String

    init(id: UUID = UUID(), sender: Sender, text: String, timeLabel: String) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timeLabel = timeLabel
    }

    var isFromUser: Bool {
        sender == .user
    }

    var isSenderUnknown: Bool {
        sender == .unknown
    }

    var groupParticipantName: String? {
        guard case .groupParticipant(let name) = sender else { return nil }
        return name
    }

    var accessibilityDescription: String {
        let senderDescription: String
        switch sender {
        case .user:
            senderDescription = String(localized: "You")
        case .otherParticipant:
            senderDescription = String(localized: "Other participant")
        case .groupParticipant(let name):
            senderDescription = String(localized: "Sender \(name)")
        case .unknown:
            senderDescription = String(localized: "Unknown sender")
        }
        if timeLabel.isEmpty {
            return String(localized: "\(senderDescription): \(text)")
        }
        return String(localized: "\(senderDescription): \(text), \(timeLabel)")
    }
}
