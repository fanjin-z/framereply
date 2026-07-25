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
    static let images = ShortcutInstallationDefinition(
        id: .images,
        title: AppStrings.Shortcut.imagesInstallationTitle,
        canonicalURLString:
            "https://www.icloud.com/shortcuts/93a5b5b855f54f8b96bc3c5117fd9df9"
    )

    static let text = ShortcutInstallationDefinition(
        id: .text,
        title: AppStrings.Shortcut.textInstallationTitle,
        canonicalURLString:
            "https://www.icloud.com/shortcuts/917551e0808543e4b779064dc2eab55d"
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
