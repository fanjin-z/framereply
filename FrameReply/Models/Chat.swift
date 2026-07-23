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
    var isProvisional: Bool = false
}
