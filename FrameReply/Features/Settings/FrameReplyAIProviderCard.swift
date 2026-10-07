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
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Text("AI replies, ready to go.")
                        .font(.footnote)
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FrameReplyColor.connected)
                        .accessibilityLabel("Selected")
                }
                Menu {
                    supportActions
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(FrameReplyColor.outline)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("FrameReply AI options")
            }

            if access.statusUnavailable {
                Text("Subscription status is temporarily unavailable.")
                    .font(.footnote)
            } else if subscribed {
                subscriberDetails
            } else {
                purchaseRow
            }

            if subscribed {
                if isSelected {
                    Text("Selected")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FrameReplyColor.connected)
                } else {
                    Button("Use FrameReply AI") {
                        requestManagedAIConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FrameReplyColor.primary)
                    .foregroundStyle(.white)
                    .disabled(busy)
                    .accessibilityIdentifier("ai-access-connect")
                }
            }

            if busy { ProgressView() }
            if let notice = connectionNotice ?? access.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
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
            guard isActive else { return }
            await access.load()
            for await _ in Storefront.updates {
                guard !Task.isCancelled else { return }
                await access.load()
            }
        }
        .onChange(of: transactionObserver.lastResult) { _, _ in
            if isActive { Task { await access.refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isActive { Task { await access.load() } }
        }
    }

    @ViewBuilder private var purchaseRow: some View {
        switch access.productAvailability {
        case .loading:
            EmptyView()
        case .available:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    offerSummary.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    subscribeButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    offerSummary
                    subscribeButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.leading, 44)
        case .notOffered:
            Text(
                "Subscription unavailable for this App Store account. You can use your own API key."
            )
            .font(.footnote)
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        case .failed:
            HStack {
                Text("Couldn’t load subscription. Try again.")
                    .font(.footnote)
                Button("Retry") { Task { await access.load() } }
                    .disabled(busy)
            }
        }
    }

    private var subscribeButton: some View {
        Button("Subscribe") {
            connectionNotice = nil
            Task {
                if await access.purchase() { requestManagedAIConnection() }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
        .tint(FrameReplyColor.primary)
        .foregroundStyle(.white)
        .disabled(busy || access.product == nil)
        .accessibilityIdentifier("ai-access-purchase")
    }

    private var offerSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let product = access.product, let period = access.billingPeriod {
                if let trial = access.trialDuration {
                    Text("\(trial) free")
                        .fontWeight(.medium)
                    Text("Then \(product.displayPrice)/\(period)")
                } else {
                    Text("\(product.displayPrice)/\(period)")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
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

    @ViewBuilder private var supportActions: some View {
        Button("Restore Purchases") {
            connectionNotice = nil
            Task {
                if await access.restore() { requestManagedAIConnection() }
            }
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

    private func requestManagedAIConnection() {
        guard !busy else { return }
        if providerStore.hasValidDataConsent(for: .frameReplyAI) {
            connectManagedAI()
        } else {
            isConnectConsentPresented = true
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
