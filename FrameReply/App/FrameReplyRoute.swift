//
//  FrameReplyRoute.swift
//  FrameReply
//

import SwiftUI

enum FrameReplyRoute: Hashable {
    case chatDetails(String)
    case chatAssistant(String)
    case chatImportReview(String)
    case newPersona
    case persona(UUID)
    case yourNames
    case privacyAndData
}
