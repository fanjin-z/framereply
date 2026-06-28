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
    private let validators: [ProviderPlatform: any ProviderValidator]
    private let providersKey = "zeptly.providerConnections.v1"
    private let activePlatformKey = "zeptly.activeProviderPlatform.v1"

    var activeProvider: ProviderConnection? {
        guard let activePlatform else {
            return nil
        }
        return providers.first { $0.platform == activePlatform }
    }

    init(
        userDefaults: UserDefaults = .standard,
        validators: [ProviderPlatform: any ProviderValidator]? = nil
    ) {
        self.userDefaults = userDefaults
        keychain = KeychainStore()
        self.validators = validators ?? [
            .openAI: OpenAIClient(),
            .zaiInternational: ZAIClient(region: .international),
            .zhipuChina: ZAIClient(region: .china)
        ]
        let loadedProviders = Self.loadProviders(from: userDefaults, key: providersKey)
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
        guard platform.isConnectable, model.isSupported(by: platform) else {
            throw ProviderConnectionError.unsupportedProvider
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw ProviderConnectionError.missingAPIKey
        }

        guard let validator = validators[platform] else {
            throw ProviderConnectionError.unsupportedProvider
        }
        try await validator.validate(apiKey: trimmedKey, model: model)

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
            model.isSupported(by: platform),
            let index = providers.firstIndex(where: { $0.platform == platform })
        else {
            return
        }
        providers[index].model = model
    }

    private func upsertConnection(platform: ProviderPlatform, model: ProviderModel) {
        let now = Date()

        if let existingIndex = providers.firstIndex(where: { $0.platform == platform }) {
            providers[existingIndex].model = model
            providers[existingIndex].lastValidatedAt = now
            providers[existingIndex].validationState = .connected
        } else {
            providers.append(
                ProviderConnection(
                    platform: platform,
                    model: model,
                    lastValidatedAt: now,
                    validationState: .connected
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

    private static func loadProviders(from userDefaults: UserDefaults, key: String) -> [ProviderConnection] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProviderConnection].self, from: data)
                .filter { provider in
                    provider.platform.isConnectable
                        && provider.model.isSupported(by: provider.platform)
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

        return providers.max { lhs, rhs in
            switch (lhs.lastValidatedAt, rhs.lastValidatedAt) {
            case let (lhsDate?, rhsDate?):
                lhsDate < rhsDate
            case (nil, _?):
                true
            case (_?, nil):
                false
            case (nil, nil):
                false
            }
        }?.platform ?? providers.first?.platform
    }

    private func keychainAccount(for platform: ProviderPlatform) -> String {
        platform.keychainAccount
    }
}
