//
//  FrameReplyRoute.swift
//  FrameReply
//

import SwiftUI

enum FrameReplyRoute: Hashable {
    case chatDetails(String)
    case chatAssistant(String)
    case newPersona
    case persona(UUID)
    case shortcutSetup
    case privacyAndData
}
