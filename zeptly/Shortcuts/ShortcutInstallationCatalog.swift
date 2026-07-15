//
//  ShortcutInstallationCatalog.swift
//  zeptly
//

import Foundation

nonisolated struct ShortcutInstallationDefinition: Equatable, Sendable {
    let title: String
    let canonicalURLString: String

    var installationURL: URL? {
        ShortcutInstallationCatalog.validatedInstallationURL(from: canonicalURLString)
    }
}

nonisolated enum ShortcutInstallationCatalog {
    // Add team-owned iCloud share URLs after both shortcuts are published and verified.
    static let images = ShortcutInstallationDefinition(
        title: "Zeptly Images",
        canonicalURLString: ""
    )

    static let text = ShortcutInstallationDefinition(
        title: "Zeptly Text",
        canonicalURLString: ""
    )

    static let all = [images, text]

    static func validatedInstallationURL(from value: String) -> URL? {
        guard
            let url = URL(string: value),
            url.scheme == "https",
            url.host?.lowercased() == "www.icloud.com"
        else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "shortcuts",
            components[1].isEmpty == false
        else {
            return nil
        }

        return url
    }
}
