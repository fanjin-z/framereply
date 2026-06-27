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

    private let userDefaults: UserDefaults
    private let keychain: KeychainStore
    private let deepSeekClient: DeepSeekClient
    private let openAIClient: OpenAIClient
    private let providersKey = "zeptly.providerConnections.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        keychain = KeychainStore()
        deepSeekClient = DeepSeekClient()
        openAIClient = OpenAIClient()
        providers = Self.loadProviders(from: userDefaults, key: providersKey)
    }

    func connect(platform: ProviderPlatform, model: ProviderModel, apiKey: String) async throws {
        guard platform.isConnectable else {
            throw ProviderConnectionError.unsupportedProvider
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw ProviderConnectionError.missingAPIKey
        }

        switch platform {
        case .deepSeek:
            try await deepSeekClient.validate(apiKey: trimmedKey, model: model)
        case .openAI:
            try await openAIClient.validate(apiKey: trimmedKey, model: model)
        }

        do {
            try keychain.set(trimmedKey, for: keychainAccount(for: platform))
        } catch let error as KeychainStoreError {
            throw ProviderConnectionError.keychainFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.keychainFailure(error.localizedDescription)
        }

        upsertConnection(platform: platform, model: model)
    }

    func savedAPIKey(for platform: ProviderPlatform) -> String? {
        try? keychain.get(account: keychainAccount(for: platform))
    }

    private func upsertConnection(platform: ProviderPlatform, model: ProviderModel) {
        let now = Date()

        if let existingIndex = providers.firstIndex(where: { $0.platform == platform }) {
            providers[existingIndex].model = model
            providers[existingIndex].lastValidatedAt = now
            providers[existingIndex].isEnabled = true
            providers[existingIndex].validationState = .connected
        } else {
            providers.append(
                ProviderConnection(
                    platform: platform,
                    model: model,
                    lastValidatedAt: now,
                    isEnabled: true,
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

    private static func loadProviders(from userDefaults: UserDefaults, key: String) -> [ProviderConnection] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProviderConnection].self, from: data)
        } catch {
            return []
        }
    }

    private func keychainAccount(for platform: ProviderPlatform) -> String {
        "provider.\(platform.rawValue).apiKey"
    }
}
