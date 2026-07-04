import Foundation
import XCTest

@testable import zeptly

final class ProviderStoreTests: XCTestCase {
    func testVisionTiersResolveToEquivalentReplyModels() {
        XCTAssertEqual(ProviderModel.gpt54Mini.suggestedReplyModel, .gpt54Mini)
        XCTAssertEqual(ProviderModel.gpt54.suggestedReplyModel, .gpt54)
        XCTAssertEqual(ProviderModel.gpt55.suggestedReplyModel, .gpt55)
        XCTAssertEqual(ProviderModel.glm46VFlashX.suggestedReplyModel, .glm47FlashX)
        XCTAssertEqual(ProviderModel.glm46VFlash.suggestedReplyModel, .glm47Flash)
        XCTAssertEqual(ProviderModel.glm46V.suggestedReplyModel, .glm47)
        XCTAssertTrue(ProviderModel.glm47.isSupported(by: .zaiInternational))
        XCTAssertFalse(ProviderPlatform.zaiInternational.supportedModels.contains(.glm47))
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
    func testFallbackAndEmptyProviderSelection() throws {
        do {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let provider = ProviderConnection(
                platform: .openAI,
                model: .gpt54Mini,
                lastValidatedAt: Date(timeIntervalSinceReferenceDate: 300),
                validationState: .connected
            )
            try saveProviders([provider], to: defaults)
            defaults.set("retiredProvider", forKey: ProviderStoreTestKey.activePlatform)

            let store = ProviderStore(userDefaults: defaults, validators: [:])

            XCTAssertEqual(store.activePlatform, .openAI)
            XCTAssertEqual(defaults.string(forKey: ProviderStoreTestKey.activePlatform), "openAI")
        }

        do {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("openAI", forKey: ProviderStoreTestKey.activePlatform)

            let store = ProviderStore(userDefaults: defaults, validators: [:])

            XCTAssertNil(store.activePlatform)
            XCTAssertNil(store.activeProvider)
            XCTAssertNil(defaults.string(forKey: ProviderStoreTestKey.activePlatform))
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
