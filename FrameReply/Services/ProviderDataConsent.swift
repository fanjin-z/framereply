import Foundation

nonisolated struct ProviderDataConsentDisclosure: Equatable, Sendable {
    static let currentVersion = 1

    let provider: ProviderPlatform

    var destinationDescription: String {
        switch provider {
        case .openAI:
            "OpenAI in the United States or another region selected by OpenAI"
        case .zaiInternational:
            "Z.ai International, which generally processes API data in Singapore"
        case .zhipuChina:
            "Zhipu AI in mainland China"
        }
    }

    var privacyPolicyURL: URL {
        switch provider {
        case .openAI:
            URL(string: "https://openai.com/policies/privacy-policy/")!
        case .zaiInternational:
            URL(string: "https://docs.z.ai/legal-agreement/privacy-policy")!
        case .zhipuChina:
            URL(string: "https://docs.bigmodel.cn/cn/terms/privacy-policy")!
        }
    }

    var permissionTitle: String {
        "Share chat content with \(provider.displayName)?"
    }

    var permissionMessage: String {
        "FrameReply will send the messages, images, names, and drafts you select directly to \(provider.displayName), a third-party AI provider, to analyze chats and create replies."
    }

    var summary: String {
        "FrameReply sends selected screenshots or message text, participant names, chat context, and drafts to \(destinationDescription) to analyze conversations and generate replies. Your provider may retain request data under its policy and may charge your provider account. FrameReply does not operate a proxy server."
    }
}

@MainActor
final class ProviderDataConsentStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasValidConsent(for platform: ProviderPlatform) -> Bool {
        userDefaults.integer(forKey: key(for: platform))
            == ProviderDataConsentDisclosure.currentVersion
    }

    func grantConsent(for platform: ProviderPlatform) {
        userDefaults.set(
            ProviderDataConsentDisclosure.currentVersion,
            forKey: key(for: platform)
        )
    }

    func revokeConsent(for platform: ProviderPlatform) {
        userDefaults.removeObject(forKey: key(for: platform))
    }

    func revokeAllConsent() {
        for platform in ProviderPlatform.availableCases {
            revokeConsent(for: platform)
        }
    }

    private func key(for platform: ProviderPlatform) -> String {
        "framereply.providerDataConsent.\(platform.rawValue).v1"
    }
}
