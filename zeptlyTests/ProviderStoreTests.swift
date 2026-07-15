import Foundation
import XCTest

@testable import zeptly

final class ProviderStoreTests: XCTestCase {
    @MainActor
    func testProviderTiersResolveToExpectedTaskModels() {
        let registry = AIProviderRegistry.live()
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .basic)?.screenshotAnalysisModel,
            .gpt56Luna
        )
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .advanced)?.suggestedReplyModel,
            .gpt56Terra
        )
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedTier: .best)?.suggestedReplyModel,
            .gpt56Sol
        )
        XCTAssertEqual(
            registry.profile(for: .zaiInternational, selectedTier: .basic)?.screenshotAnalysisModel,
            .glm46VFlash
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedTier: .basic)?.suggestedReplyModel,
            .glm47Flash
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedTier: .basic)?.transcriptAnalysisModel,
            .glm47Flash
        )
        XCTAssertEqual(
            registry.profile(for: .zaiInternational, selectedTier: .advanced)?
                .screenshotAnalysisModel,
            .glm46VFlashX
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedTier: .advanced)?.suggestedReplyModel,
            .glm47FlashX
        )
        XCTAssertEqual(
            registry.profile(for: .zaiInternational, selectedTier: .best)?.screenshotAnalysisModel,
            .glm46V
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedTier: .best)?.suggestedReplyModel,
            .glm47
        )
    }

    @MainActor
    func testProviderCatalogAndModelCompatibility() throws {
        XCTAssertEqual(ProviderPlatform.allCases, [.openAI, .zaiInternational, .zhipuChina])
        XCTAssertEqual(
            ProviderPlatform.zaiInternational.supportedTiers,
            [.basic, .advanced, .best]
        )
        XCTAssertNotEqual(
            ProviderPlatform.zaiInternational.keychainAccount,
            ProviderPlatform.zhipuChina.keychainAccount
        )
        XCTAssertTrue(ProviderPlatform.allCases.allSatisfy { $0.defaultTier == .advanced })
        XCTAssertEqual(
            ProviderPlatform.openAI.modelSummary(for: .advanced),
            "gpt-5.6-terra"
        )
        XCTAssertEqual(
            ProviderPlatform.zaiInternational.modelSummary(for: .advanced),
            "glm-4.6v-flashx"
        )

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        let store = ProviderStore(userDefaults: defaults)

        store.setTier(.best, for: .zaiInternational)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .zaiInternational })?.tier,
            .best
        )

        store.setTier(.basic, for: .zhipuChina)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .zhipuChina })?.tier,
            .basic
        )

        let savedData = try XCTUnwrap(defaults.data(forKey: ProviderStoreTestKey.providers))
        let savedProviders = try JSONDecoder().decode([ProviderConnection].self, from: savedData)
        XCTAssertEqual(
            savedProviders.first(where: { $0.platform == .zaiInternational })?.tier,
            .best
        )
    }

    @MainActor
    func testPersistedActivationIsExclusiveAndSurvivesReload() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("zaiInternational", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(store.activePlatform, .zaiInternational)

        store.activate(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.activeProvider?.platform, .openAI)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")

        let reloadedStore = ProviderStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.activePlatform, .openAI)
        XCTAssertEqual(reloadedStore.activeProvider?.platform, .openAI)
    }

    @MainActor
    func testFallbackAndEmptyProviderSelection() throws {
        do {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            try saveProviders(makeProviders(), to: defaults)
            defaults.set("retiredProvider", forKey: ProviderStoreTestKey.activePlatform)

            let store = ProviderStore(userDefaults: defaults)

            XCTAssertEqual(store.activePlatform, .zaiInternational)
            XCTAssertEqual(
                defaults.string(forKey: ProviderStoreTestKey.activePlatform),
                "zaiInternational"
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
        defaults.set("zaiInternational", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        try keychain.set("secret", for: ProviderPlatform.openAI.keychainAccount)
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.remove(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .zaiInternational)
        XCTAssertFalse(store.providers.contains(where: { $0.platform == .openAI }))
        XCTAssertNil(try keychain.get(account: ProviderPlatform.openAI.keychainAccount))

        try assertRemovingActiveProviderSelectsFollowingProviderAndPersists()
    }

    @MainActor
    private func assertRemovingActiveProviderSelectsFollowingProviderAndPersists() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("zhipuChina", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.remove(platform: .zhipuChina)

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.providers.map(\.platform), [.zaiInternational, .openAI])

        let reloadedStore = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )
        XCTAssertEqual(reloadedStore.activePlatform, .openAI)
        XCTAssertEqual(reloadedStore.providers.map(\.platform), [.zaiInternational, .openAI])
    }

    @MainActor
    func testKeychainDeletionFailureLeavesProviderStateUnchanged() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("zhipuChina", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        keychain.failingDeleteAccounts.insert(ProviderPlatform.zhipuChina.keychainAccount)
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        XCTAssertThrowsError(try store.remove(platform: .zhipuChina))

        XCTAssertEqual(store.providers.map(\.platform), makeProviders().map(\.platform))
        XCTAssertEqual(store.activePlatform, .zhipuChina)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "zhipuChina")
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
                platform: .zaiInternational,
                tier: .advanced
            ),
            ProviderConnection(
                platform: .zhipuChina,
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
    static let providers = "zeptly.providerConnections.v2"
    static let activePlatform = "zeptly.activeProviderPlatform.v1"
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
