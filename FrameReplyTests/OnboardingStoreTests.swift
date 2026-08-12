import Foundation
import XCTest

@testable import FrameReply

final class OnboardingStoreTests: XCTestCase {
    @MainActor
    func testFreshInstallationNormalizesMissingValueToPendingInitialOnboarding() {
        withDefaults { defaults in
            let store = OnboardingStore(userDefaults: defaults)

            XCTAssertEqual(store.lastCompletedVersion, OnboardingVersion.none)
            XCTAssertEqual(store.presentation, .initial)
            XCTAssertEqual(
                defaults.integer(forKey: OnboardingStore.storageKey),
                OnboardingVersion.none
            )
            XCTAssertNotNil(defaults.object(forKey: OnboardingStore.storageKey))
        }
    }

    @MainActor
    func testInterruptedFreshOnboardingRemainsPendingAfterInstallationMarkerAppears() {
        withDefaults { defaults in
            _ = OnboardingStore(userDefaults: defaults)
            defaults.set(true, forKey: ProviderStore.installationMarkerKey)

            let relaunchedStore = OnboardingStore(userDefaults: defaults)

            XCTAssertEqual(relaunchedStore.lastCompletedVersion, OnboardingVersion.none)
            XCTAssertEqual(relaunchedStore.presentation, .initial)
        }
    }

    @MainActor
    func testLegacyInstallationNormalizesToCompletedInitialOnboarding() {
        withDefaults { defaults in
            defaults.set(true, forKey: ProviderStore.installationMarkerKey)

            let store = OnboardingStore(userDefaults: defaults)

            XCTAssertEqual(store.lastCompletedVersion, OnboardingVersion.initial)
            XCTAssertEqual(store.presentation, .none)
        }
    }

    @MainActor
    func testOlderCompletedVersionReceivesCurrentUpdateOnce() {
        withDefaults { defaults in
            defaults.set(OnboardingVersion.initial, forKey: OnboardingStore.storageKey)
            let store = OnboardingStore(userDefaults: defaults, currentVersion: 2)

            XCTAssertEqual(store.presentation, .update)

            store.completeCurrentOnboarding()

            XCTAssertEqual(store.lastCompletedVersion, 2)
            XCTAssertEqual(store.presentation, .none)
            XCTAssertEqual(defaults.integer(forKey: OnboardingStore.storageKey), 2)
        }
    }

    @MainActor
    func testFutureFreshInstallationStillReceivesInitialSetup() {
        withDefaults { defaults in
            let store = OnboardingStore(userDefaults: defaults, currentVersion: 2)

            XCTAssertEqual(store.lastCompletedVersion, OnboardingVersion.none)
            XCTAssertEqual(store.presentation, .initial)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
