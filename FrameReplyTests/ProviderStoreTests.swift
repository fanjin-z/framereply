import Foundation
import XCTest

@testable import FrameReply

final class ProviderStoreTests: XCTestCase {
    @MainActor
    func testProviderConnectionRequiresPersistedConsentBeforeSaving() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = TestKeychainStore()
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        do {
            try await store.connect(
                platform: .openAI,
                tier: .advanced,
                apiKey: "synthetic-key"
            )
            XCTFail("Expected consentRequired")
        } catch let error as ProviderConnectionError {
            guard case .dataConsentRequired = error else {
                return XCTFail("Expected dataConsentRequired, got \(error)")
            }
        }

        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertNil(store.activePlatform)
        XCTAssertNil(try keychain.get(account: ProviderPlatform.openAI.keychainAccount))
    }

    @MainActor
    func testProviderCatalogTiersAndModelCompatibility() throws {
        let registry = AIProviderRegistry.live()
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .basic)?.screenshotAnalysisModel,
            .gpt6Luna
        )
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .advanced)?.suggestedReplyModel,
            .gpt56Terra
        )
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .best)?.suggestedReplyModel,
            .gpt6Sol
        )
        XCTAssertEqual(
            registry.profile(for: .openRouter, selectedTier: .advanced),
            ProviderModelProfile(
                screenshotAnalysisModel: .qwen37Plus,
                transcriptAnalysisModel: .qwen37Plus,
                suggestedReplyModel: .qwen37Plus
            )
        )
        XCTAssertTrue(
            [ProviderTier.basic, .best].allSatisfy {
                registry.profile(for: .openRouter, selectedTier: $0) == nil
            }
        )
        for platform in [ProviderPlatform.miniMaxInternational, .miniMaxChina] {
            XCTAssertEqual(platform.supportedTiers, [.advanced])
            XCTAssertEqual(
                registry.profile(for: platform, selectedTier: .advanced),
                ProviderModelProfile(
                    screenshotAnalysisModel: .miniMaxM3,
                    transcriptAnalysisModel: .miniMaxM3,
                    suggestedReplyModel: .miniMaxM3
                )
            )
            XCTAssertNil(registry.profile(for: platform, selectedTier: .basic))
            XCTAssertNil(registry.profile(for: platform, selectedTier: .best))
            XCTAssertEqual(platform.modelSummary(for: .advanced), "MiniMax M3")
        }
        XCTAssertEqual(
            ProviderPlatform.allCases,
            [.openAI, .openRouter, .miniMaxInternational, .miniMaxChina, .frameReplyAI]
        )
        XCTAssertEqual(
            ProviderPlatform.availableCases,
            [.openAI, .openRouter, .miniMaxInternational, .miniMaxChina]
        )
        XCTAssertEqual(ProviderPlatform.openRouter.supportedTiers, [.advanced])
        XCTAssertEqual(ProviderPlatform.openRouter.displayName, "OpenRouter")
        XCTAssertEqual(
            ProviderPlatform.openRouter.modelSummary(for: .advanced),
            "Qwen3.7 Plus"
        )
        XCTAssertNotEqual(
            ProviderPlatform.miniMaxInternational.keychainAccount,
            ProviderPlatform.miniMaxChina.keychainAccount
        )
        XCTAssertEqual(ProviderPlatform.openAI.defaultTier, .basic)
        XCTAssertTrue(
            [ProviderPlatform.openRouter, .miniMaxInternational, .miniMaxChina]
                .allSatisfy { $0.defaultTier == .advanced }
        )
        XCTAssertEqual(ProviderPlatform.openAI.modelSummary(for: .basic), "GPT-6 Luna")
        XCTAssertEqual(
            ProviderPlatform.openAI.modelSummary(for: .advanced),
            "GPT-5.6 Terra"
        )
        XCTAssertEqual(ProviderPlatform.openAI.modelSummary(for: .best), "GPT-6 Sol")
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        let store = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .openAI })?.tier,
            .basic
        )

        store.setTier(.best, for: .openAI)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .openAI })?.tier,
            .best
        )

        let reloadedStore = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(
            reloadedStore.providers.first(where: { $0.platform == .openAI })?.tier,
            .best
        )
    }

    @MainActor
    func testProviderSelectionPersistsAndFallsBackSafely() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("miniMaxInternational", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(store.activePlatform, .miniMaxInternational)

        store.activate(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.activeProvider?.platform, .openAI)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")

        let reloadedStore = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.activePlatform, .openAI)
        XCTAssertEqual(reloadedStore.activeProvider?.platform, .openAI)

        do {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            try saveProviders(makeProviders(), to: defaults)
            defaults.set("retiredProvider", forKey: ProviderStoreTestKey.activePlatform)

            let store = ProviderStore(userDefaults: defaults)

            XCTAssertEqual(store.activePlatform, .miniMaxInternational)
            XCTAssertEqual(
                defaults.string(forKey: ProviderStoreTestKey.activePlatform),
                "miniMaxInternational"
            )
        }

        do {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)

            let store = ProviderStore(userDefaults: defaults)

            XCTAssertNil(store.activePlatform)
            XCTAssertNil(store.activeProvider)
            XCTAssertNil(defaults.string(forKey: ProviderStoreTestKey.activePlatform))
        }
    }

    @MainActor
    func testProviderRemovalUpdatesCredentialsSelectionAndPersistence() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("miniMaxInternational", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        try keychain.set("secret", for: ProviderPlatform.openAI.keychainAccount)
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.remove(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .miniMaxInternational)
        XCTAssertFalse(store.providers.contains(where: { $0.platform == .openAI }))
        XCTAssertNil(try keychain.get(account: ProviderPlatform.openAI.keychainAccount))

        try assertRemovingActiveProviderSelectsFollowingProviderAndPersists()
    }

    @MainActor
    func testMiniMaxRegionalConnectionsPersistActivateAndRemoveIndependently() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(
            [
                ProviderConnection(platform: .miniMaxInternational, tier: .advanced),
                ProviderConnection(platform: .miniMaxChina, tier: .advanced)
            ], to: defaults)
        defaults.set("miniMaxChina", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        try keychain.set(
            "international-key", for: ProviderPlatform.miniMaxInternational.keychainAccount)
        try keychain.set("china-key", for: ProviderPlatform.miniMaxChina.keychainAccount)

        let store = ProviderStore(
            userDefaults: defaults, registry: .live(), keychain: keychain)
        XCTAssertEqual(store.providers.map(\.platform), [.miniMaxInternational, .miniMaxChina])
        XCTAssertEqual(store.activePlatform, .miniMaxChina)

        try store.remove(platform: .miniMaxInternational)

        XCTAssertEqual(store.providers.map(\.platform), [.miniMaxChina])
        XCTAssertEqual(store.activePlatform, .miniMaxChina)
        XCTAssertNil(
            try keychain.get(account: ProviderPlatform.miniMaxInternational.keychainAccount))
        XCTAssertEqual(
            try keychain.get(account: ProviderPlatform.miniMaxChina.keychainAccount), "china-key")

        let reloaded = ProviderStore(
            userDefaults: defaults, registry: .live(), keychain: keychain)
        XCTAssertEqual(reloaded.providers.map(\.platform), [.miniMaxChina])
        XCTAssertEqual(reloaded.activePlatform, .miniMaxChina)
    }

    @MainActor
    func testManagedCredentialIsSeparateAndExpiresClosed() throws {
        let modelID = try XCTUnwrap(ManagedOpenRouterModelID(rawValue: "openai/future-model"))
        let model = ManagedOpenRouterModel(requestID: modelID, responseID: modelID)
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(
            [
                ProviderConnection(
                    platform: .frameReplyAI, tier: .basic,
                    managedModel: model,
                    managedExpiresAt: Date().addingTimeInterval(3600))
            ],
            to: defaults)
        defaults.set("frameReplyAI", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        try keychain.set("capped-key", for: ProviderPlatform.frameReplyAI.keychainAccount)
        let store = ProviderStore(
            userDefaults: defaults, registry: .live(), keychain: keychain)

        XCTAssertEqual(store.savedAPIKey(for: .frameReplyAI), "capped-key")
        XCTAssertNil(store.savedAPIKey(for: .openRouter))
        store.providers[0].managedExpiresAt = Date().addingTimeInterval(-1)
        XCTAssertNil(store.savedAPIKey(for: .frameReplyAI))
    }

    @MainActor
    private func assertRemovingActiveProviderSelectsFollowingProviderAndPersists() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("miniMaxChina", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.remove(platform: .miniMaxChina)

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.providers.map(\.platform), [.miniMaxInternational, .openAI])

        let reloadedStore = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )
        XCTAssertEqual(reloadedStore.activePlatform, .openAI)
        XCTAssertEqual(reloadedStore.providers.map(\.platform), [.miniMaxInternational, .openAI])
    }

    @MainActor
    func testKeychainDeletionFailureLeavesProviderStateUnchanged() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("miniMaxChina", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        keychain.failingDeleteAccounts.insert(ProviderPlatform.miniMaxChina.keychainAccount)
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        XCTAssertThrowsError(try store.remove(platform: .miniMaxChina))

        XCTAssertEqual(store.providers.map(\.platform), makeProviders().map(\.platform))
        XCTAssertEqual(store.activePlatform, .miniMaxChina)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "miniMaxChina")
    }

    @MainActor
    func testFullProviderDeletionRemovesDefaultsConsentAndEveryCredential() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)
        defaults.set("remove-me", forKey: "framereply.testPreference")
        defaults.set(OnboardingVersion.initial, forKey: OnboardingStore.storageKey)
        ProviderDataConsentStore(userDefaults: defaults).grantConsent(for: .openAI)
        let keychain = TestKeychainStore()
        for platform in ProviderPlatform.allCases {
            try keychain.set("secret", for: platform.keychainAccount)
        }
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.deleteAllProviderData()

        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertNil(store.activePlatform)
        XCTAssertNil(defaults.object(forKey: "framereply.testPreference"))
        XCTAssertEqual(
            defaults.integer(forKey: OnboardingStore.storageKey),
            OnboardingVersion.initial
        )
        XCTAssertFalse(store.hasValidDataConsent(for: .openAI))
        for platform in ProviderPlatform.allCases {
            XCTAssertNil(try keychain.get(account: platform.keychainAccount))
        }
    }

    @MainActor
    func testFreshInstallationPurgesOrphanedKeychainCredentials() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = TestKeychainStore()
        for platform in ProviderPlatform.allCases {
            try keychain.set("orphan", for: platform.keychainAccount)
        }

        _ = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain,
            reconcileInstallation: true
        )

        for platform in ProviderPlatform.allCases {
            XCTAssertNil(try keychain.get(account: platform.keychainAccount))
        }
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ProviderStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeProviders() -> [ProviderConnection] {
        [
            ProviderConnection(
                platform: .miniMaxInternational,
                tier: .advanced
            ),
            ProviderConnection(
                platform: .miniMaxChina,
                tier: .advanced
            ),
            ProviderConnection(
                platform: .openAI,
                tier: .basic
            )
        ]
    }

    private func saveProviders(
        _ providers: [ProviderConnection],
        to defaults: UserDefaults
    ) throws {
        defaults.set(
            try JSONEncoder().encode(providers),
            forKey: ProviderStoreTestKey.providers
        )
    }
}

private enum ProviderStoreTestKey {
    static let providers = "framereply.providerConnections.v1"
    static let activePlatform = "framereply.activeProviderPlatform.v1"
}

private final class TestKeychainStore: KeychainStoring {
    var failingDeleteAccounts: Set<String> = []
    private var values: [String: String] = [:]

    func set(_ value: String, for account: String) throws {
        values[account] = value
    }

    func get(account: String) throws -> String? {
        values[account]
    }

    func delete(account: String) throws {
        if failingDeleteAccounts.contains(account) {
            throw TestKeychainError.deleteFailed
        }
        values.removeValue(forKey: account)
    }
}

private enum TestKeychainError: Error {
    case deleteFailed
}
