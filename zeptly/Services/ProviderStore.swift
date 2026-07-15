//
//  ProviderStore.swift
//  zeptly
//

import Combine
import Foundation

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
    private let providersKey = "zeptly.providerConnections.v2"
    private let activePlatformKey = "zeptly.activeProviderPlatform.v1"

    var activeProvider: ProviderConnection? {
        guard let activePlatform else {
            return nil
        }
        return providers.first { $0.platform == activePlatform }
    }

    convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, registry: .live())
    }

    convenience init(userDefaults: UserDefaults, registry: AIProviderRegistry) {
        self.init(
            userDefaults: userDefaults,
            registry: registry,
            keychain: KeychainStore()
        )
    }

    init(
        userDefaults: UserDefaults,
        registry: AIProviderRegistry,
        keychain: any KeychainStoring
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.registry = registry
        let loadedProviders = Self.loadProviders(
            from: userDefaults,
            key: providersKey,
            registry: registry
        )
        providers = loadedProviders
        activePlatform = Self.loadActivePlatform(
            from: userDefaults,
            key: activePlatformKey,
            providers: loadedProviders
        )
        saveProviders()
        saveActivePlatform()
    }

    func connect(platform: ProviderPlatform, tier: ProviderTier, apiKey: String) async throws {
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
        try? keychain.get(account: keychainAccount(for: platform))
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

        try keychain.delete(account: keychainAccount(for: platform))

        if activePlatform == platform {
            let nextIndex = providers.index(after: removedIndex)
            activePlatform =
                nextIndex < providers.endIndex
                ? providers[nextIndex].platform
                : providers.first(where: { $0.platform != platform })?.platform
        }

        providers.remove(at: removedIndex)
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
        do {
            let data = try JSONEncoder().encode(providers)
            userDefaults.set(data, forKey: providersKey)
        } catch {
            assertionFailure("Failed to save providers: \(error)")
        }
    }

    private func saveActivePlatform() {
        if let activePlatform {
            userDefaults.set(activePlatform.rawValue, forKey: activePlatformKey)
        } else {
            userDefaults.removeObject(forKey: activePlatformKey)
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
}
