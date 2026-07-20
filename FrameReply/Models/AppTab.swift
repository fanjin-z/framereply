//
//  AppTab.swift
//  FrameReply
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case inbox
    case personas
    case settings

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .inbox: "Inbox"
        case .personas: "Personas"
        case .settings: "Settings"
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var previous: AppTab? {
        guard index > Self.allCases.startIndex else {
            return nil
        }

        return Self.allCases[index - 1]
    }

    var next: AppTab? {
        let nextIndex = index + 1
        guard Self.allCases.indices.contains(nextIndex) else {
            return nil
        }

        return Self.allCases[nextIndex]
    }

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
