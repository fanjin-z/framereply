import Foundation

nonisolated struct ProviderDataConsentDisclosure: Equatable, Sendable {
    static let currentVersion = 1

    let provider: ProviderPlatform

    var destinationDescription: String {
        switch provider {
        case .openAI:
            String(localized: AppStrings.Provider.openAIDestination)
        case .openRouter:
            String(localized: AppStrings.Provider.openRouterDestination)
        case .frameReplyAI:
            String(localized: "OpenRouter and the model provider selected by FrameReply")
        case .miniMaxInternational:
            String(localized: AppStrings.Provider.miniMaxInternationalDestination)
        case .miniMaxChina:
            String(localized: AppStrings.Provider.miniMaxChinaDestination)
        }
    }

    var privacyPolicyURL: URL {
        switch provider {
        case .openAI:
            URL(string: "https://openai.com/policies/privacy-policy/")!
        case .openRouter:
            URL(string: "https://openrouter.ai/privacy")!
        case .frameReplyAI:
            URL(string: "https://openrouter.ai/privacy")!
        case .miniMaxInternational:
            URL(string: "https://platform.minimax.io/protocol/privacy-policy")!
        case .miniMaxChina:
            URL(string: "https://platform.minimaxi.com/zh/protocol/privacy-policy")!
        }
    }

    var permissionTitle: String {
        String(localized: AppStrings.Provider.consentTitle(providerName: provider.displayName))
    }

    var permissionMessage: String {
        if provider == .frameReplyAI {
            return String(
                localized:
                    "Selected messages, screenshots, names, context, and drafts go directly from this device to OpenRouter and its model provider. FrameReply's backend verifies your subscription and issues a capped AI key; it does not receive your AI content."
            )
        }
        return String(
            localized: AppStrings.Provider.consentMessage(providerName: provider.displayName))
    }

    var summary: String {
        if provider == .frameReplyAI {
            return String(
                localized:
                    "Selected AI content goes directly to OpenRouter and its model provider. FrameReply's backend handles subscription verification and key limits, without receiving your AI content. The provider may retain request data under its policy."
            )
        }
        return String(
            localized: AppStrings.Provider.consentSummary(destination: destinationDescription))
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
        for platform in ProviderPlatform.allCases {
            revokeConsent(for: platform)
        }
    }

    private func key(for platform: ProviderPlatform) -> String {
        "framereply.providerDataConsent.\(platform.rawValue).v1"
    }
}
