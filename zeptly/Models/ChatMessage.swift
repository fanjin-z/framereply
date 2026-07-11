//
//  ChatMessage.swift
//  zeptly
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
}
