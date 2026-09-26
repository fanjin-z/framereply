//
//  ProviderStore.swift
//  FrameReply
//

import Combine
import Foundation
import StoreKit

@MainActor
final class ProviderStore: ObservableObject {
    @Published var providers: [ProviderConnection] {
        didSet {
            saveProviders()
        }
    }
    @Published private(set) var activePlatform: ProviderPlatform? {
        didSet {
            saveActivePlatform()
        }
    }

    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring
    private let registry: AIProviderRegistry
    private let consentStore: ProviderDataConsentStore
    private static let providersKey = "framereply.providerConnections.v1"
    private static let activePlatformKey = "framereply.activeProviderPlatform.v1"
    nonisolated static let installationMarkerKey = "framereply.installationMarker.v1"
    private var isResetting = false
    private var managedRefresh: Task<Void, Error>?

    var activeProvider: ProviderConnection? {
        guard let activePlatform else {
            return nil
        }
        return providers.first { $0.platform == activePlatform }
    }

    convenience init(userDefaults: UserDefaults = .standard) {
        self.init(
            userDefaults: userDefaults,
            registry: .live(),
            keychain: KeychainStore(),
            reconcileInstallation: true
        )
    }

    convenience init(userDefaults: UserDefaults, registry: AIProviderRegistry) {
        self.init(
            userDefaults: userDefaults,
            registry: registry,
            keychain: KeychainStore(),
            reconcileInstallation: true
        )
    }

    init(
        userDefaults: UserDefaults,
        registry: AIProviderRegistry,
        keychain: any KeychainStoring,
        reconcileInstallation: Bool = false
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.registry = registry
        consentStore = ProviderDataConsentStore(userDefaults: userDefaults)
        if reconcileInstallation {
            Self.reconcileInstallation(
                userDefaults: userDefaults,
                keychain: keychain,
                markerKey: Self.installationMarkerKey
            )
        }
        let loadedProviders = Self.loadProviders(
            from: userDefaults,
            key: Self.providersKey,
            registry: registry
        )
        providers = loadedProviders
        activePlatform = Self.loadActivePlatform(
            from: userDefaults,
            key: Self.activePlatformKey,
            providers: loadedProviders
        )
        saveProviders()
        saveActivePlatform()
    }

    func connect(
        platform: ProviderPlatform,
        tier: ProviderTier,
        apiKey: String
    ) async throws {
        guard platform != .frameReplyAI else {
            throw ProviderConnectionError.unsupportedProvider
        }
        guard consentStore.hasValidConsent(for: platform) else {
            throw ProviderConnectionError.dataConsentRequired
        }
        guard registry.profile(for: platform, selectedTier: tier) != nil
        else {
            throw ProviderConnectionError.unsupportedProvider
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw ProviderConnectionError.missingAPIKey
        }

        do {
            try await AIService(registry: registry).validate(
                platform: platform,
                selectedTier: tier,
                apiKey: trimmedKey
            )
        } catch is AIServiceError {
            throw ProviderConnectionError.unsupportedProvider
        }

        do {
            try keychain.set(trimmedKey, for: keychainAccount(for: platform))
        } catch let error as KeychainStoreError {
            throw ProviderConnectionError.keychainFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.keychainFailure(error.localizedDescription)
        }

        upsertConnection(platform: platform, tier: tier)
        activate(platform: platform)
    }

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        if platform == .frameReplyAI {
            guard let connection = providers.first(where: { $0.platform == platform }),
                connection.managedModel != nil,
                let expiry = connection.managedExpiresAt,
                expiry > Date()
            else { return nil }
        }
        return try? keychain.get(account: keychainAccount(for: platform))
    }

    func connectManagedAI() async throws {
        guard consentStore.hasValidConsent(for: .frameReplyAI) else {
            throw ProviderConnectionError.dataConsentRequired
        }
        try await refreshManagedAI(activate: true)
    }

    func prepareManagedAIIfNeeded() async throws {
        guard activePlatform == .frameReplyAI else { return }
        if let connection = activeProvider,
            let expiry = connection.managedExpiresAt,
            expiry > Date().addingTimeInterval(60),
            savedAPIKey(for: .frameReplyAI) != nil
        {
            return
        }
        if let managedRefresh {
            try await managedRefresh.value
            return
        }
        let task = Task { try await refreshManagedAI(activate: false) }
        managedRefresh = task
        defer { managedRefresh = nil }
        try await task.value
    }

    private func refreshManagedAI(activate: Bool) async throws {
        guard consentStore.hasValidConsent(for: .frameReplyAI) else {
            throw ProviderConnectionError.dataConsentRequired
        }
        let configuration = try SubscriptionConfiguration.load()
        guard let evidence = await Transaction.latest(for: configuration.productID) else {
            throw SubscriptionClientError(
                message: String(
                    localized:
                        "No Apple subscription was found. Open AI Providers in Settings."))
        }
        let client = SubscriptionClient(configuration: configuration)
        let entitlement = try await client.verifyAndFinish(evidence)
        guard entitlement.active else {
            throw SubscriptionClientError(
                message: String(
                    localized:
                        "Your AI Access subscription is inactive."))
        }
        let usage = try await client.usage(
            serviceSubscriptionId: entitlement.serviceSubscriptionId)
        guard usage.periodId == entitlement.period.id,
            usage.kind == entitlement.period.kind,
            !usage.stale, usage.remainingMicrousd.map({ $0 > 0 }) == true,
            usage.availability == "available"
        else {
            throw SubscriptionClientError(
                message: String(
                    localized:
                        "AI allowance is unavailable or exhausted."))
        }
        let credential = try await client.credential(
            serviceSubscriptionId: entitlement.serviceSubscriptionId)
        guard credential.aiProvider == "openrouter",
            let requestID = ManagedOpenRouterModelID(rawValue: credential.model),
            let responseID = ManagedOpenRouterModelID(rawValue: credential.responseModel),
            credential.apiKey.hasPrefix("sk-or-v1-"),
            let expiry = AIAccessPresentation.date(credential.expiresAt),
            let accessEnd = AIAccessPresentation.date(entitlement.accessUntil),
            expiry > Date().addingTimeInterval(60),
            expiry <= accessEnd
        else {
            throw SubscriptionClientError(
                message: String(
                    localized:
                        "FrameReply returned an invalid AI credential."))
        }
        let model = ManagedOpenRouterModel(requestID: requestID, responseID: responseID)
        guard !Task.isCancelled,
            consentStore.hasValidConsent(for: .frameReplyAI),
            activate || activePlatform == .frameReplyAI
        else { throw CancellationError() }
        try keychain.set(credential.apiKey, for: keychainAccount(for: .frameReplyAI))
        if let index = providers.firstIndex(where: { $0.platform == .frameReplyAI }) {
            var updated = providers[index]
            updated.managedModel = model
            updated.managedExpiresAt = expiry
            providers[index] = updated
        } else {
            providers.append(
                ProviderConnection(
                    platform: .frameReplyAI, tier: .basic,
                    managedModel: model, managedExpiresAt: expiry))
        }
        if activate { self.activate(platform: .frameReplyAI) }
    }

    func hasValidDataConsent(for platform: ProviderPlatform) -> Bool {
        consentStore.hasValidConsent(for: platform)
    }

    func grantDataConsent(for platform: ProviderPlatform) {
        consentStore.grantConsent(for: platform)
    }

    func revokeDataConsent(for platform: ProviderPlatform) {
        consentStore.revokeConsent(for: platform)
    }

    func activate(platform: ProviderPlatform) {
        guard providers.contains(where: { $0.platform == platform }) else {
            return
        }
        activePlatform = platform
    }

    func setTier(_ tier: ProviderTier, for platform: ProviderPlatform) {
        guard
            registry.profile(for: platform, selectedTier: tier) != nil,
            let index = providers.firstIndex(where: { $0.platform == platform })
        else {
            return
        }
        providers[index].tier = tier
    }

    func remove(platform: ProviderPlatform) throws {
        guard let removedIndex = providers.firstIndex(where: { $0.platform == platform }) else {
            return
        }

        if platform == .frameReplyAI { managedRefresh?.cancel() }

        try keychain.delete(account: keychainAccount(for: platform))
        consentStore.revokeConsent(for: platform)

        if activePlatform == platform {
            let nextIndex = providers.index(after: removedIndex)
            activePlatform =
                nextIndex < providers.endIndex
                ? providers[nextIndex].platform
                : providers.first(where: { $0.platform != platform })?.platform
        }

        providers.remove(at: removedIndex)
    }

    func deleteAllProviderData() throws {
        for platform in ProviderPlatform.allCases {
            try keychain.delete(account: keychainAccount(for: platform))
        }

        isResetting = true
        defer { isResetting = false }
        providers = []
        activePlatform = nil
        let storedKeys = userDefaults.dictionaryRepresentation().keys
        for key in storedKeys where key != OnboardingStore.storageKey {
            userDefaults.removeObject(forKey: key)
        }
        consentStore.revokeAllConsent()
        userDefaults.set(true, forKey: Self.installationMarkerKey)
    }

    private func upsertConnection(platform: ProviderPlatform, tier: ProviderTier) {
        if let existingIndex = providers.firstIndex(where: { $0.platform == platform }) {
            providers[existingIndex].tier = tier
        } else {
            providers.append(
                ProviderConnection(
                    platform: platform,
                    tier: tier
                )
            )
        }
    }

    private func saveProviders() {
        guard isResetting == false else { return }
        do {
            let data = try JSONEncoder().encode(providers)
            userDefaults.set(data, forKey: Self.providersKey)
        } catch {
            assertionFailure("Failed to save providers: \(error)")
        }
    }

    private func saveActivePlatform() {
        guard isResetting == false else { return }
        if let activePlatform {
            userDefaults.set(activePlatform.rawValue, forKey: Self.activePlatformKey)
        } else {
            userDefaults.removeObject(forKey: Self.activePlatformKey)
        }
    }

    private static func loadProviders(
        from userDefaults: UserDefaults,
        key: String,
        registry: AIProviderRegistry
    ) -> [ProviderConnection] {
        guard let data = userDefaults.data(forKey: key),
            let providers = try? JSONDecoder().decode([ProviderConnection].self, from: data)
        else {
            return []
        }
        return providers.filter {
            registry.profile(for: $0.platform, selectedTier: $0.tier) != nil
                && ($0.platform != .frameReplyAI
                    || ($0.managedModel != nil
                        && $0.managedExpiresAt != nil))
        }
    }

    private static func loadActivePlatform(
        from userDefaults: UserDefaults,
        key: String,
        providers: [ProviderConnection]
    ) -> ProviderPlatform? {
        guard providers.isEmpty == false else {
            return nil
        }

        if let rawValue = userDefaults.string(forKey: key),
            let savedPlatform = ProviderPlatform(rawValue: rawValue),
            providers.contains(where: { $0.platform == savedPlatform })
        {
            return savedPlatform
        }

        return providers.first?.platform
    }

    private func keychainAccount(for platform: ProviderPlatform) -> String {
        platform.keychainAccount
    }

    private static func reconcileInstallation(
        userDefaults: UserDefaults,
        keychain: any KeychainStoring,
        markerKey: String
    ) {
        guard userDefaults.bool(forKey: markerKey) == false else { return }

        do {
            for platform in ProviderPlatform.allCases {
                try keychain.delete(account: platform.keychainAccount)
            }
            userDefaults.set(true, forKey: markerKey)
        } catch {
            // Leave the marker unset so a later launch retries cleanup.
        }
    }
}
