//
//  AppTab.swift
//  zeptly
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case personas = "Personas"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .inbox:
            "bubble.left"
        case .personas:
            "face.smiling"
        case .settings:
            "gearshape"
        }
    }
}
