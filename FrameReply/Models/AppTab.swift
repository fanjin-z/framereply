//
//  AppTab.swift
//  FrameReply
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case chats
    case personas
    case settings

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .chats: "Chats"
        case .personas: "Personas"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .chats:
            "bubble.left"
        case .personas:
            "face.smiling"
        case .settings:
            "gearshape"
        }
    }
}
