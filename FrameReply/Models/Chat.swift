//
//  Chat.swift
//  FrameReply
//

import Foundation
import SwiftUI

struct Chat: Identifiable {
    let id: String
    let name: String
    let preview: String
    let avatarSymbol: String?
    let initials: String
    let gradient: [Color]
    let updatedAt: Date
    let conversationKind: ChatConversationKind
    var isProvisional: Bool
    var requiresImportReview: Bool

    init(
        id: String,
        name: String,
        preview: String,
        avatarSymbol: String?,
        initials: String,
        gradient: [Color],
        updatedAt: Date,
        conversationKind: ChatConversationKind = .direct,
        isProvisional: Bool = false,
        requiresImportReview: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.avatarSymbol = avatarSymbol
        self.initials = initials
        self.gradient = gradient
        self.updatedAt = updatedAt
        self.conversationKind = conversationKind
        self.isProvisional = isProvisional
        self.requiresImportReview = requiresImportReview ?? isProvisional
    }
}
