import Foundation
import XCTest
@testable import zeptly

final class ProviderStoreTests: XCTestCase {
    @MainActor
    func testLegacyProvidersChooseMostRecentlyValidatedAsActive() throws {
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

        XCTAssertEqual(store.providers.count, 2)
        XCTAssertEqual(store.activePlatform, .openAI)
        XCTAssertEqual(store.activeProvider?.id, openAI.id)
        XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")
    }

    @MainActor
    func testPersistedActivationIsExclusiveAndSurvivesReload() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        defaults.set("deepSeek", forKey: ProviderStoreTestKey.activePlatform)

        let store = ProviderStore(userDefaults: defaults, validators: [:])
        XCTAssertEqual(store.activePlatform, .deepSeek)

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
    func testModelChangesPersistImmediatelyAndRejectWrongPlatform() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try saveProviders(makeProviders(), to: defaults)
        let store = ProviderStore(userDefaults: defaults, validators: [:])

        store.setModel(.deepSeekV4Flash, for: .deepSeek)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .deepSeek })?.model,
            .deepSeekV4Flash
        )

        store.setModel(.gpt55, for: .deepSeek)
        XCTAssertEqual(
            store.providers.first(where: { $0.platform == .deepSeek })?.model,
            .deepSeekV4Flash
        )

        let savedData = try XCTUnwrap(defaults.data(forKey: ProviderStoreTestKey.providers))
        let savedProviders = try JSONDecoder().decode([ProviderConnection].self, from: savedData)
        XCTAssertEqual(
            savedProviders.first(where: { $0.platform == .deepSeek })?.model,
            .deepSeekV4Flash
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
                platform: .deepSeek,
                model: .deepSeekV4Pro,
                lastValidatedAt: Date(timeIntervalSinceReferenceDate: 100),
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
