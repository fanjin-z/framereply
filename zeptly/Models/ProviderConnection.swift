//
//  ProviderConnection.swift
//  zeptly
//

import SwiftUI

struct ProviderConnection: Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let symbolName: String
    let lastSynced: String
    var isEnabled: Bool
}
