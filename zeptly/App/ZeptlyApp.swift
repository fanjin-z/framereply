//
//  zeptlyApp.swift
//  zeptly
//
//  Created by Fanjin Zeng on 3/15/26.
//

import AppIntents
import SwiftUI

@main
struct ZeptlyApp: App {
    init() {
        ZeptlyShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
