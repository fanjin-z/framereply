//
//  ScreenshotShortcutConfiguration.swift
//  zeptly
//

import Foundation

nonisolated enum ScreenshotShortcutConfiguration {
    /// The team-owned iCloud share URL for the "Capture with Zeptly" shortcut.
    /// Replace this value after publishing the canonical shortcut from Shortcuts.
    static let canonicalURLString = ""

    static var installationURL: URL? {
        validatedInstallationURL(from: canonicalURLString)
    }

    static func validatedInstallationURL(from value: String) -> URL? {
        guard
            let url = URL(string: value),
            url.scheme == "https",
            url.host?.lowercased() == "www.icloud.com"
        else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "shortcuts", components[1].isEmpty == false
        else {
            return nil
        }

        return url
    }
}
