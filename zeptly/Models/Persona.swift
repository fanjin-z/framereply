//
//  Persona.swift
//  zeptly
//

import SwiftUI

struct Persona: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let symbolName: String
    let accent: Color
    let tags: [String]
}
