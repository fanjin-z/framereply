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
        String(localized: AppStrings.Provider.consentMessage(providerName: provider.displayName))
    }

    var summary: String {
        String(localized: AppStrings.Provider.consentSummary(destination: destinationDescription))
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
