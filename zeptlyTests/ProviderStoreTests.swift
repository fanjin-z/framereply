import Foundation
import XCTest

@testable import zeptly

final class ProviderStoreTests: XCTestCase {
    @MainActor
    func testVisionTiersResolveToEquivalentReplyModels() {
        let registry = AIProviderRegistry.live()
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedModel: .gpt54Mini)?.suggestedReplyModel,
            .gpt54Mini
        )
        XCTAssertEqual(
            registry.profile(for: .openAI, selectedModel: .gpt55)?.screenshotAnalysisModel,
            .gpt55
        )
        XCTAssertEqual(
            registry.profile(for: .zaiInternational, selectedModel: .glm46VFlashX)?.suggestedReplyModel,
            .glm47FlashX
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedModel: .glm46VFlash)?.suggestedReplyModel,
            .glm47Flash
        )
        XCTAssertEqual(
            registry.profile(for: .zhipuChina, selectedModel: .glm46V)?.suggestedReplyModel,
            .glm47
        )
        XCTAssertNil(registry.profile(for: .zaiInternational, selectedModel: .glm47))
    }

    @MainActor
    func testProviderCatalogAndModelCompatibility() throws {
        XCTAssertEqual(ProviderPlatform.allCases, [.openAI, .zaiInternational, .zhipuChina])
        XCTAssertEqual(
            ProviderPlatform.zaiInternational.supportedModels,
            ProviderPlatform.zhipuChina.supportedModels
        )
        XCTAssertNotEqual(
            ProviderPlatform.zaiInternational.keychainAccount,
            ProviderPlatform.zhipuChina.keychainAccount
        )

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        let store = ProviderStore(userDefaults: defaults)

        store.setModel(.glm46V, for: .zaiInternational)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .zaiInternational })?.model,
            .glm46V
        )

        store.setModel(.glm46VFlash, for: .zhipuChina)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .zhipuChina })?.model,
            .glm46VFlash
        )

        store.setModel(.gpt55, for: .zaiInternational)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .zaiInternational })?.model,
            .glm46V
        )

        let savedData = try XCTUnwrap(defaults.data(forKey: ProviderStoreTestKey.providers))
        let savedProviders = try JSONDecoder().decode([ProviderConnection].self, from: savedData)
        XCTAssertEqual(
            savedProviders.first(where: { $0.platform == .zaiInternational })?.model,
            .glm46V
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
    func testLegacyProviderMetadataIsIgnoredWhenLoading() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let providerID = UUID()
        let legacyJSON = """
        [{
          "id": "\(providerID.uuidString)",
          "platform": "openAI",
          "model": "gpt-5.4-mini",
          "lastValidatedAt": 300,
          "validationState": "connected"
        }]
        """
        defaults.set(
            try XCTUnwrap(legacyJSON.data(using: .utf8)),
            forKey: ProviderStoreTestKey.providers
        )

        let store = ProviderStore(userDefaults: defaults)

        XCTAssertEqual(store.providers.count, 1)
        XCTAssertEqual(store.providers.first?.id, providerID)
        XCTAssertEqual(store.providers.first?.platform, .openAI)
        XCTAssertEqual(store.providers.first?.model, .gpt54Mini)
    }

    @MainActor
    func testRemovingInactiveProviderPreservesActiveSelectionAndDeletesKey() throws {
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
    }

    @MainActor
    func testRemovingActiveMiddleProviderSelectsFollowingProviderAndPersists() throws {
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
    func testRemovingActiveFinalProviderWrapsToFirstProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: TestKeychainStore()
        )

        try store.remove(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .zaiInternational)
        XCTAssertEqual(store.providers.map(\.platform), [.zaiInternational, .zhipuChina])
    }

    @MainActor
    func testRemovingOnlyProviderClearsSelectionAndPersistence() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(
            [ProviderConnection(platform: .openAI, model: .gpt54Mini)],
            to: defaults
        )
        defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)
        let keychain = TestKeychainStore()
        let store = ProviderStore(
            userDefaults: defaults,
            registry: .live(),
            keychain: keychain
        )

        try store.remove(platform: .openAI)

        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertNil(store.activePlatform)
        XCTAssertNil(defaults.string(forKey: ProviderStoreTestKey.activePlatform))

        let savedData = try XCTUnwrap(defaults.data(forKey: ProviderStoreTestKey.providers))
        XCTAssertTrue(try JSONDecoder().decode([ProviderConnection].self, from: savedData).isEmpty)
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
                model: .glm46VFlashX
            ),
            ProviderConnection(
                platform: .zhipuChina,
                model: .glm46VFlashX
            ),
            ProviderConnection(
                platform: .openAI,
                model: .gpt54Mini
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
    static let providers = "zeptly.providerConnections.v1"
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
