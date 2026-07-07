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
    private let keychain: KeychainStore
    private let registry: AIProviderRegistry
    private let providersKey = "zeptly.providerConnections.v1"
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

    init(userDefaults: UserDefaults, registry: AIProviderRegistry) {
        self.userDefaults = userDefaults
        keychain = KeychainStore()
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

    func connect(platform: ProviderPlatform, model: ProviderModel, apiKey: String) async throws {
        guard platform.isConnectable, registry.profile(for: platform, selectedModel: model) != nil else {
            throw ProviderConnectionError.unsupportedProvider
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw ProviderConnectionError.missingAPIKey
        }

        do {
            try await AIService(registry: registry).validate(
                platform: platform,
                selectedModel: model,
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

        upsertConnection(platform: platform, model: model)
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

    func setModel(_ model: ProviderModel, for platform: ProviderPlatform) {
        guard
            registry.profile(for: platform, selectedModel: model) != nil,
            let index = providers.firstIndex(where: { $0.platform == platform })
        else {
            return
        }
        providers[index].model = model
    }

    private func upsertConnection(platform: ProviderPlatform, model: ProviderModel) {
        if let existingIndex = providers.firstIndex(where: { $0.platform == platform }) {
            providers[existingIndex].model = model
        } else {
            providers.append(
                ProviderConnection(
                    platform: platform,
                    model: model
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
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProviderConnection].self, from: data)
                .filter { provider in
                    provider.platform.isConnectable
                        && registry.profile(
                            for: provider.platform,
                            selectedModel: provider.model
                        ) != nil
                }
        } catch {
            return []
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

        if
            let rawValue = userDefaults.string(forKey: key),
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
