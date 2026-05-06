//
//  zeptlyApp.swift
//  zeptly
//
//  Created by Fanjin Zeng on 3/15/26.
//

import SwiftUI
import AppIntents

@main
struct zeptlyApp: App {
    init() {
        ZeptlyShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
