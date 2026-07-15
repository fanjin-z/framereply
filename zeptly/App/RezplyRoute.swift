//
//  RezplyRoute.swift
//  zeptly
//

import SwiftUI

enum RezplyRoute: Hashable {
    case chatDetails(String)
    case chatAssistant(String)
    case newPersona
    case persona(UUID)
    case shortcutSetup
    case privacyAndData
}
