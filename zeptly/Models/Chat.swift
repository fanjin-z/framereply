//
//  Chat.swift
//  zeptly
//

import SwiftUI

struct Chat: Identifiable {
    let id: String
    let name: String
    let preview: String
    let chipTitle: String
    let chipSymbol: String
    let avatarSymbol: String?
    let avatarData: Data?
    let initials: String
    let gradient: [Color]
    let isUnread: Bool
    let contactContext: ContactContext?
    var isProvisional: Bool = false
}
