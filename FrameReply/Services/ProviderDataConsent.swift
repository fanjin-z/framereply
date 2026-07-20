import Foundation

nonisolated struct ProviderDataConsentDisclosure: Equatable, Sendable {
    static let currentVersion = 1

    let provider: ProviderPlatform

    var destinationDescription: String {
        switch provider {
        case .openAI:
            String(localized: AppStrings.Provider.openAIDestination)
        case .zaiInternational:
            String(localized: AppStrings.Provider.zaiInternationalDestination)
        case .zhipuChina:
            String(localized: AppStrings.Provider.zhipuChinaDestination)
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
