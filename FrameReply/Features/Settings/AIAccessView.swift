import StoreKit
import SwiftUI

struct AIAccessView: View {
    @StateObject private var access: AIAccessModel
    @ObservedObject var providerStore: ProviderStore
    @ObservedObject private var transactionObserver = SubscriptionTransactionObserver.shared
    @State private var isManageSubscriptionsPresented = false
    @State private var isConnectConsentPresented = false
    @State private var isConnecting = false
    @State private var connectionNotice: String?

    init(configuration: SubscriptionConfiguration, providerStore: ProviderStore) {
        _access = StateObject(wrappedValue: AIAccessModel(configuration: configuration))
        self.providerStore = providerStore
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    subscriptionCard
                    statusCard
                    if let usage = access.usage, access.entitlement?.active == true {
                        allowanceCard(usage)
                    } else if access.entitlement?.active == true,
                        let usageIssue = access.usageIssue
                    {
                        card {
                            Text("AI allowance")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(usageIssue)
                                .font(.footnote)
                        }
                    }
                    actionCard
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("AI Access")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ai-access-screen")
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        .alert(
            "Share chat content with AI providers?",
            isPresented: $isConnectConsentPresented
        ) {
            Button("Not Now", role: .cancel) {}
            Button("Allow & Connect") {
                providerStore.grantDataConsent(for: .frameReplyAI)
                connectManagedAI()
            }
        } message: {
            Text(ProviderDataConsentDisclosure(provider: .frameReplyAI).permissionMessage)
        }
        .task { await access.load() }
        .onChange(of: transactionObserver.lastResult) { _, _ in
            Task { await access.refresh() }
        }
        .onChange(of: isManageSubscriptionsPresented) { _, isPresented in
            if !isPresented { Task { await access.refresh() } }
        }
    }

    private var subscriptionCard: some View {
        card {
            Label("AI Access Monthly", systemImage: "sparkles")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)

            Text("An alternative to bringing your own AI provider key.")
                .font(.subheadline)
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            if let product = access.product {
                if access.hasSevenDayTrial {
                    Text("7 days free, then \(product.displayPrice) per month.")
                        .font(.headline)
                } else {
                    Text("\(product.displayPrice) per month.")
                        .font(.headline)
                }
                Text("Subscription renews automatically unless you cancel it in the App Store.")
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            } else if access.isBusy {
                ProgressView("Loading Apple subscription…")
            } else {
                Text("Apple subscription pricing is unavailable. Try again later.")
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            #if DEBUG
                Text("Sandbox testing only.")
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            #endif
        }
    }

    private var statusCard: some View {
        card {
            Text("Subscription status")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            if access.statusUnavailable {
                Text("Subscription status is temporarily unavailable.")
            } else if let entitlement = access.entitlement {
                if entitlement.active && entitlement.period.kind == "trial" {
                    Text("Free trial active")
                } else if entitlement.active {
                    Text("Subscription active")
                } else {
                    Text("No active subscription")
                }

                if entitlement.active,
                    let endDate = AIAccessPresentation.date(entitlement.accessUntil)
                {
                    Text("Access through \(endDate, format: .dateTime.month().day().year())")
                        .font(.footnote)
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                if entitlement.active && !entitlement.willRenew {
                    Text("Automatic renewal is off.")
                        .font(.footnote)
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
            } else {
                Text("No subscription found for this Apple Account.")
            }
        }
    }

    private func allowanceCard(_ usage: SubscriptionUsage) -> some View {
        card {
            if usage.kind == "trial" {
                Text("Trial AI allowance")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            } else {
                Text("AI allowance")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }

            Text("Total: \(AIAccessPresentation.usd(usage.budgetMicrousd))")

            if !usage.stale, let remaining = usage.remainingMicrousd {
                Text("Remaining: \(AIAccessPresentation.usd(remaining))")
            } else {
                Text("Current usage is temporarily unavailable.")
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

        }
    }

    private var actionCard: some View {
        card {
            if access.entitlement?.active == true {
                if providerStore.activePlatform == .frameReplyAI {
                    Label("FrameReply AI Access is selected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FrameReplyColor.connected)
                } else {
                    Button("Use FrameReply AI Access") {
                        if providerStore.hasValidDataConsent(for: .frameReplyAI) {
                            connectManagedAI()
                        } else {
                            isConnectConsentPresented = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(access.isBusy || isConnecting)
                    .accessibilityIdentifier("ai-access-connect")
                }
                Text("AI requests go directly to the model provider using a capped key.")
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            if access.entitlement?.active != true {
                Button {
                    Task { await access.purchase() }
                } label: {
                    Group {
                        if access.hasSevenDayTrial {
                            Text("Start Free Trial")
                        } else {
                            Text("Subscribe")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(access.isBusy || access.statusUnavailable || access.product == nil)
                .accessibilityIdentifier("ai-access-purchase")
            }

            Button("Restore Purchases") {
                Task { await access.restore() }
            }
            .disabled(access.isBusy)
            .accessibilityIdentifier("ai-access-restore")

            Button("Refresh Status") {
                Task { await access.refresh() }
            }
            .disabled(access.isBusy)

            if access.entitlement != nil {
                Button("Manage Subscription") {
                    isManageSubscriptionsPresented = true
                }
                .disabled(access.isBusy)
                .accessibilityIdentifier("ai-access-manage")
            }

            HStack(spacing: 20) {
                Link("Terms of Use", destination: AppLegalLinks.url(for: .terms))
                Link("Privacy Policy", destination: AppLegalLinks.url(for: .privacy))
            }
            .font(.footnote)

            if access.isBusy || isConnecting { ProgressView() }
            if let connectionNotice {
                Text(connectionNotice)
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            if let notice = access.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
        }
    }

    private func connectManagedAI() {
        guard !isConnecting else { return }
        isConnecting = true
        connectionNotice = nil
        Task {
            defer { isConnecting = false }
            do {
                try await providerStore.connectManagedAI()
                connectionNotice = String(localized: "FrameReply AI Access is ready to use.")
                await access.refresh()
            } catch {
                connectionNotice = error.localizedDescription
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .foregroundStyle(FrameReplyColor.onSurface)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 18))
    }
}
