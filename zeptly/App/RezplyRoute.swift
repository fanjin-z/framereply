//
//  RezplyRoute.swift
//  zeptly
//

import SwiftUI

enum RezplyRoute: Hashable {
    case contactContext(String)
    case chatIntelligence(String)
    case newPersona
    case persona(UUID)
}
