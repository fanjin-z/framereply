import Combine
import Foundation

/// Coordinates consent and connection without choosing a screen's presentation.
@MainActor
final class FrameReplyAIConnectionModel: ObservableObject {
    let consentRequested = PassthroughSubject<ManagedAIConsent, Never>()
    @Published private(set) var isConnecting = false
    @Published private(set) var notice: String?

    private let access: AIAccessModel
    private let providerStore: ProviderStore
    private let onConnected: (() -> Void)?
    private let onConnectionStateChanged: ((Bool) -> Void)?

    var isBusy: Bool { access.isBusy || access.isInitiallyLoading || isConnecting }

    init(
        access: AIAccessModel,
        providerStore: ProviderStore,
        onConnected: (() -> Void)? = nil,
        onConnectionStateChanged: ((Bool) -> Void)? = nil
    ) {
        self.access = access
        self.providerStore = providerStore
        self.onConnected = onConnected
        self.onConnectionStateChanged = onConnectionStateChanged
    }

    func purchase() {
        guard !isBusy else { return }
        notice = nil
        Task {
            if await access.purchase() { requestConnection() }
        }
    }

    func restore() {
        guard !isBusy else { return }
        notice = nil
        Task {
            if await access.restore() { requestConnection() }
        }
    }

    func refresh(refreshAppTransaction: Bool = false) {
        guard !isBusy else { return }
        notice = nil
        Task { await access.refresh(refreshAppTransaction: refreshAppTransaction) }
    }

    func requestConnection() {
        guard !isBusy else { return }
        isConnecting = true
        onConnectionStateChanged?(true)
        notice = nil
        Task {
            do {
                let consent = try await access.aiConsent()
                isConnecting = false
                onConnectionStateChanged?(false)
                if providerStore.hasValidDataConsent(for: consent) {
                    connect()
                } else {
                    consentRequested.send(consent)
                }
            } catch {
                isConnecting = false
                onConnectionStateChanged?(false)
                notice = error.localizedDescription
            }
        }
    }

    func allowConnection(_ consent: ManagedAIConsent) {
        providerStore.grantManagedDataConsent(consent)
        connect()
    }

    private func connect() {
        guard !isBusy else { return }
        isConnecting = true
        onConnectionStateChanged?(true)
        notice = nil
        Task {
            defer {
                isConnecting = false
                onConnectionStateChanged?(false)
            }
            do {
                try await providerStore.connectManagedAI()
                onConnected?()
                await access.refreshUsageIfNeeded(force: true)
            } catch {
                notice = error.localizedDescription
            }
        }
    }
}
