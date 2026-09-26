import StoreKit
import SwiftUI

struct FrameReplyAIProviderCard: View {
    @StateObject private var access: AIAccessModel
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool
    @ObservedObject private var transactionObserver = SubscriptionTransactionObserver.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConnectConsentPresented = false
    @State private var isConnecting = false
    @State private var connectionNotice: String?

    init(configuration: SubscriptionConfiguration, providerStore: ProviderStore, isActive: Bool) {
        _access = StateObject(wrappedValue: AIAccessModel(configuration: configuration))
        self.providerStore = providerStore
        self.isActive = isActive
    }

    private var isSelected: Bool { providerStore.activePlatform == .frameReplyAI }
    private var subscribed: Bool { access.entitlement?.active == true }
    private var busy: Bool { access.isBusy || isConnecting }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FrameReply AI")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("AI replies without your own API key.")
                        .font(.footnote)
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FrameReplyColor.connected)
                        .accessibilityLabel("Selected")
                }
            }

            if access.statusUnavailable {
                Text("Subscription status is temporarily unavailable.")
                    .font(.footnote)
            } else if subscribed {
                subscriberDetails
            } else {
                purchaseDetails
            }

            if subscribed {
                if isSelected {
                    Text("Selected")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FrameReplyColor.connected)
                } else {
                    Button("Use FrameReply AI") {
                        if providerStore.hasValidDataConsent(for: .frameReplyAI) {
                            connectManagedAI()
                        } else {
                            isConnectConsentPresented = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    .accessibilityIdentifier("ai-access-connect")
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { supportActions }
                VStack(alignment: .leading, spacing: 12) { supportActions }
            }
            .font(.footnote)
            if subscribed {
                Text("Manage or cancel in Settings > Apple Account > Subscriptions.")
                    .font(.caption)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            HStack(spacing: 20) {
                Link("Terms of Use", destination: AppLegalLinks.url(for: .terms))
                Link("Privacy Policy", destination: AppLegalLinks.url(for: .privacy))
            }
            .font(.caption)

            if busy { ProgressView() }
            if let notice = connectionNotice ?? access.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            #if DEBUG
                Text("Sandbox testing only.")
                    .font(.caption)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            #endif
        }
        .foregroundStyle(FrameReplyColor.onSurface)
        .padding(16)
        .accessibilityIdentifier("provider-row-frameReplyAI")
        .alert("Share chat content with AI providers?", isPresented: $isConnectConsentPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Allow & Connect") {
                providerStore.grantDataConsent(for: .frameReplyAI)
                connectManagedAI()
            }
        } message: {
            Text(ProviderDataConsentDisclosure(provider: .frameReplyAI).permissionMessage)
        }
        .task(id: isActive) {
            if isActive { await access.load() }
        }
        .onChange(of: transactionObserver.lastResult) { _, _ in
            if isActive { Task { await access.refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isActive { Task { await access.refresh() } }
        }
    }

    private var subscriberDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if access.entitlement?.period.kind == "trial" {
                Text("Free trial active")
            } else {
                Text("Subscription active")
            }
            if let usage = access.usage,
                let fraction = AIAccessPresentation.remainingFraction(usage)
            {
                Text(usage.kind == "trial" ? "Trial AI allowance" : "AI allowance")
                    .font(.footnote.weight(.semibold))
                ProgressView(value: fraction)
                    .tint(
                        AIAccessPresentation.usageLevel(fraction) == .available
                            ? FrameReplyColor.primary : .orange
                    )
                    .accessibilityLabel("AI allowance remaining")
                    .accessibilityValue(usageLabel(fraction))
                Text(usageLabel(fraction))
                    .font(.footnote)
                if fraction == 0 {
                    Text("You can switch to a provider using your own API key.")
                        .font(.footnote)
                }
            } else {
                Text("Current usage is temporarily unavailable.")
                    .font(.footnote)
            }
            if let entitlement = access.entitlement,
                let date = AIAccessPresentation.date(entitlement.accessUntil)
            {
                if entitlement.willRenew {
                    Text("Next renewal: \(date, format: .dateTime.month().day().year())")
                } else {
                    Text("Access through \(date, format: .dateTime.month().day().year())")
                    Text("Automatic renewal is off.")
                }
            }
        }
        .font(.footnote)
    }

    private var purchaseDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let product = access.product {
                if access.hasSevenDayTrial {
                    Text("7 days free, then \(product.displayPrice) per month.")
                        .font(.headline)
                } else {
                    Text("\(product.displayPrice) per month.")
                        .font(.headline)
                }
                Text(
                    "Includes a limited AI allowance each subscription period. Trial usage is also limited."
                )
                .font(.footnote)
                Text("Subscription renews automatically unless you cancel it in the App Store.")
                    .font(.footnote)
                Button {
                    connectionNotice = nil
                    Task { await access.purchase() }
                } label: {
                    Text(access.hasSevenDayTrial ? "Start Free Trial" : "Subscribe")
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .accessibilityIdentifier("ai-access-purchase")
            } else {
                Text("Apple subscription pricing is unavailable. Try again later.")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder private var supportActions: some View {
        Button("Restore Purchases") {
            connectionNotice = nil
            Task { await access.restore() }
        }
        .disabled(busy)
        .accessibilityIdentifier("ai-access-restore")
        Button("Refresh Status") {
            connectionNotice = nil
            Task { await access.load() }
        }
        .disabled(busy)
    }

    private func usageLabel(_ fraction: Double) -> LocalizedStringKey {
        switch AIAccessPresentation.usageLevel(fraction) {
        case .available: "Available"
        case .low: "Running low"
        case .exhausted: "Period limit reached"
        }
    }

    private func connectManagedAI() {
        guard !busy else { return }
        isConnecting = true
        connectionNotice = nil
        Task {
            defer { isConnecting = false }
            do {
                try await providerStore.connectManagedAI()
                await access.refresh()
            } catch {
                connectionNotice = error.localizedDescription
            }
        }
    }
}
