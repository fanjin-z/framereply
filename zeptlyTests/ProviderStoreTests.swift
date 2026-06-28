import Foundation
import XCTest
@testable import zeptly

final class ProviderStoreTests: XCTestCase {
    func testVisionProvidersAndRegionalCredentialAccountsAreDistinct() {
        XCTAssertEqual(ProviderPlatform.allCases, [.openAI, .zaiInternational, .zhipuChina])
        XCTAssertFalse(ProviderPlatform.allCases.contains(.deepSeek))
        XCTAssertEqual(ProviderPlatform.zaiInternational.supportedModels, ProviderPlatform.zhipuChina.supportedModels)
        XCTAssertNotEqual(ProviderPlatform.zaiInternational.keychainAccount, ProviderPlatform.zhipuChina.keychainAccount)
    }

    @MainActor
    func testLegacyDeepSeekConnectionIsMigratedOutOfActiveProviders() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let deepSeek = LegacyProviderConnection(
            id: UUID(),
            platform: .deepSeek,
            model: .deepSeekV4Pro,
            lastValidatedAt: Date(timeIntervalSinceReferenceDate: 100),
            isEnabled: true,
            validationState: .connected
        )
        let openAI = LegacyProviderConnection(
            id: UUID(),
            platform: .openAI,
            model: .gpt54Mini,
            lastValidatedAt: Date(timeIntervalSinceReferenceDate: 200),
            isEnabled: true,
            validationState: .connected
        )
        defaults.set(
            try JSONEncoder().encode([deepSeek, openAI]),
            forKey: ProviderStoreTestKey.providers
        )

        let store = ProviderStore(userDefaults: defaults, validators: [:])

        XCTAssertEqual(store.providers.count, 1)
        XCTAssertFalse(store.providers.contains { $0.platform == .deepSeek })
        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.activeProvider?.id, openAI.id)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")
        let migratedData = try XCTUnwrap(defaults.data(forKey: ProviderStoreTestKey.providers))
        let migratedProviders = try JSONDecoder().decode([ProviderConnection].self, from: migratedData)
        XCTAssertEqual(migratedProviders.map(\.platform), [.openAI])
    }

    @MainActor
    func testPersistedActivationIsExclusiveAndSurvivesReload() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("zaiInternational", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults, validators: [:])
        XCTAssertEqual(store.activePlatform, .zaiInternational)

        store.activate(platform: .openAI)

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.activeProvider?.platform, .openAI)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")

        let reloadedStore = ProviderStore(userDefaults: defaults, validators: [:])
        XCTAssertEqual(reloadedStore.activePlatform, .openAI)
        XCTAssertEqual(reloadedStore.activeProvider?.platform, .openAI)
    }

    @MainActor
    func testUnavailablePersistedPlatformFallsBackToNewestProvider() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProviderConnection(
            platform: .openAI,
            model: .gpt54Mini,
            lastValidatedAt: Date(timeIntervalSinceReferenceDate: 300),
            validationState: .connected
        )
        try saveProviders([provider], to: defaults)
        defaults.set("deepSeek", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults, validators: [:])

        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")
    }

    @MainActor
    func testSharedZAIModelsWorkInBothRegionsAndRejectOpenAIModels() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        let store = ProviderStore(userDefaults: defaults, validators: [:])

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
    func testEmptyProviderListHasNoActivePlatform() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults, validators: [:])

        XCTAssertNil(store.activePlatform)
        XCTAssertNil(store.activeProvider)
        XCTAssertNil(defaults.string(forKey: ProviderStoreTestKey.activePlatform))
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
                model: .glm46VFlashX,
                lastValidatedAt: Date(timeIntervalSinceReferenceDate: 100),
                validationState: .connected
            ),
            ProviderConnection(
                platform: .zhipuChina,
                model: .glm46VFlashX,
                lastValidatedAt: Date(timeIntervalSinceReferenceDate: 150),
                validationState: .connected
            ),
            ProviderConnection(
                platform: .openAI,
                model: .gpt54Mini,
                lastValidatedAt: Date(timeIntervalSinceReferenceDate: 200),
                validationState: .connected
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

private struct LegacyProviderConnection: Encodable {
    let id: UUID
    let platform: ProviderPlatform
    let model: ProviderModel
    let lastValidatedAt: Date?
    let isEnabled: Bool
    let validationState: ProviderValidationState
}
