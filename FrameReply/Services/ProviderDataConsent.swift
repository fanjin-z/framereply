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
        return String(
            localized: AppStrings.Provider.consentMessage(providerName: provider.displayName))
    }

    var summary: String {
        return String(
            localized: AppStrings.Provider.consentSummary(destination: destinationDescription))
    }
}

nonisolated struct ManagedAIConsent: Codable, Equatable, Sendable {
    struct Recipient: Codable, Equatable, Sendable {
        let id: String
        let name: String
    }
    let version: String
    let recipients: [Recipient]

    var isValid: Bool {
        version.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            && (1...10).contains(recipients.count)
            && Set(recipients.map(\.id)).count == recipients.count
            && recipients.allSatisfy {
                $0.id.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil
                    && !$0.name.isEmpty && $0.name.count <= 80
                    && $0.name == $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.name.rangeOfCharacter(from: .controlCharacters) == nil
            }
    }

    var recipientNames: String {
        let formatter = ListFormatter()
        formatter.locale = LocalizationContext.current.locale
        return formatter.string(from: recipients.map(\.name))
            ?? recipients.map(\.name).joined(separator: ", ")
    }

    var permissionMessage: String {
        String(localized: AppStrings.Provider.managedConsentMessage(recipients: recipientNames))
    }

    var summary: String {
        String(localized: AppStrings.Provider.managedConsentSummary(recipients: recipientNames))
    }
}

@MainActor
final class ProviderDataConsentStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private let managedKey = "framereply.managedAIConsent.v1"

    var managedConsent: ManagedAIConsent? {
        guard let data = userDefaults.data(forKey: managedKey),
            let consent = try? JSONDecoder().decode(ManagedAIConsent.self, from: data),
            consent.isValid
        else { return nil }
        return consent
    }

    func hasValidConsent(for consent: ManagedAIConsent) -> Bool {
        consent.isValid && managedConsent == consent
    }

    func grantConsent(_ consent: ManagedAIConsent) {
        guard consent.isValid, let data = try? JSONEncoder().encode(consent) else { return }
        userDefaults.set(data, forKey: managedKey)
    }

    func hasValidConsent(for platform: ProviderPlatform) -> Bool {
        guard platform != .frameReplyAI else { return false }
        return userDefaults.integer(forKey: key(for: platform))
            == ProviderDataConsentDisclosure.currentVersion
    }

    func grantConsent(for platform: ProviderPlatform) {
        guard platform != .frameReplyAI else { return }
        userDefaults.set(
            ProviderDataConsentDisclosure.currentVersion,
            forKey: key(for: platform)
        )
    }

    func revokeConsent(for platform: ProviderPlatform) {
        if platform == .frameReplyAI { userDefaults.removeObject(forKey: managedKey) }
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
