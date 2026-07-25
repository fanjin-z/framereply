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
        canonicalURLString: "https://www.icloud.com/shortcuts/4f8858f795de4507ad43c36f5d8deb2c"
    )

    static let text = ShortcutInstallationDefinition(
        id: .text,
        title: AppStrings.Shortcut.textInstallationTitle,
        canonicalURLString: "https://www.icloud.com/shortcuts/8577cb5408bc42cdbd8fe3dd4dad5a23"
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
