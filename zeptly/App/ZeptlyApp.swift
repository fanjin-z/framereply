//
//  zeptlyApp.swift
//  zeptly
//
//  Created by Fanjin Zeng on 3/15/26.
//

import SwiftData
import SwiftUI

@main
struct ZeptlyApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = ZeptlyDataStore.shared
        do {
            try ChatRepository(container: modelContainer).seedIfNeeded()
            try PersonaRepository(container: modelContainer).seedPersonasIfNeeded()
        } catch {
            assertionFailure("Unable to seed Zeptly data: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
