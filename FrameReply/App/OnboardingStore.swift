import Combine
import Foundation

nonisolated enum OnboardingVersion {
    static let none = 0
    static let initial = 1
    static let current = initial
}

nonisolated enum OnboardingPresentation: Equatable {
    case none
    case initial
    case update
}

@MainActor
final class OnboardingStore: ObservableObject {
    nonisolated static let storageKey = "framereply.lastCompletedOnboardingVersion"

    @Published private(set) var lastCompletedVersion: Int

    private let userDefaults: UserDefaults
    private let currentVersion: Int

    init(
        userDefaults: UserDefaults = .standard,
        installationMarkerKey: String = ProviderStore.installationMarkerKey,
        currentVersion: Int = OnboardingVersion.current
    ) {
        self.userDefaults = userDefaults
        self.currentVersion = currentVersion

        let normalizedVersion: Int
        if userDefaults.object(forKey: Self.storageKey) != nil {
            normalizedVersion = max(
                OnboardingVersion.none,
                userDefaults.integer(forKey: Self.storageKey)
            )
        } else if userDefaults.bool(forKey: installationMarkerKey) {
            normalizedVersion = OnboardingVersion.initial
        } else {
            normalizedVersion = OnboardingVersion.none
        }

        lastCompletedVersion = normalizedVersion
        userDefaults.set(normalizedVersion, forKey: Self.storageKey)
    }

    var presentation: OnboardingPresentation {
        if lastCompletedVersion == OnboardingVersion.none {
            return .initial
        }
        if lastCompletedVersion < currentVersion {
            return .update
        }
        return .none
    }

    func completeCurrentOnboarding() {
        lastCompletedVersion = currentVersion
        userDefaults.set(currentVersion, forKey: Self.storageKey)
    }
}
