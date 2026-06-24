//
//  ChatMessage.swift
//  zeptly
//

import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Sender: Equatable {
        case contact
        case user
        case other(String)
    }

    let id = UUID()
    let sender: Sender
    let text: String
    let timeLabel: String

    var isFromUser: Bool {
        sender == .user
    }
}
