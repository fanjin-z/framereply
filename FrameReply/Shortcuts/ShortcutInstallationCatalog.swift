//
//  ShortcutInstallationCatalog.swift
//  FrameReply
//

import Foundation

nonisolated enum ShortcutInstallationID: String, Sendable {
    case images
    case text
}

nonisolated struct ShortcutInstallationDefinition: Sendable {
    let id: ShortcutInstallationID
    let title: LocalizedStringResource
    let canonicalURLString: String

    var installationURL: URL? {
        ShortcutInstallationCatalog.validatedInstallationURL(from: canonicalURLString)
    }
}

nonisolated enum ShortcutInstallationCatalog {
    // Add team-owned iCloud share URLs after both shortcuts are published and verified.
    static let images = ShortcutInstallationDefinition(
        id: .images,
        title: AppStrings.Shortcut.imagesInstallationTitle,
        canonicalURLString: ""
    )

    static let text = ShortcutInstallationDefinition(
        id: .text,
        title: AppStrings.Shortcut.textInstallationTitle,
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
