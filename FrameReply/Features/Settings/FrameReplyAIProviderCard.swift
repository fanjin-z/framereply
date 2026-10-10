import StoreKit
import SwiftUI

struct FrameReplyAIProviderCard: View {
    @ObservedObject var access: AIAccessModel
    @ObservedObject var providerStore: ProviderStore
    @StateObject private var connection: FrameReplyAIConnectionModel

    private var isSelected: Bool { providerStore.activePlatform == .frameReplyAI }
    private var subscribed: Bool { access.hasActiveSubscription }
    private var busy: Bool { connection.isBusy }

    init(access: AIAccessModel, providerStore: ProviderStore) {
        self.access = access
        self.providerStore = providerStore
        _connection = StateObject(
            wrappedValue: FrameReplyAIConnectionModel(access: access, providerStore: providerStore)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeader

            if !access.isInitiallyLoading || busy {
                VStack(alignment: .leading, spacing: 8) {
                    if !access.isInitiallyLoading {
                        if access.statusUnavailable {
                            Text(
                                connection.notice ?? access.notice
                                    ?? String(
                                        localized: "Subscription status is temporarily unavailable."
                                    )
                            )
                            if access.configuration == nil {
                                Button("Retry") {
                                    connection.refresh(refreshAppTransaction: true)
                                }
                                .disabled(busy)
                            }
                        } else if subscribed {
                            subscriberDetails
                        } else {
                            purchaseRow
                        }
                    }

                    if busy { ProgressView() }
                    if !access.statusUnavailable, let notice = connection.notice ?? access.notice {
                        Text(notice)
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .padding(.leading, 60)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(FrameReplyColor.onSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider-row-frameReplyAI")
        .modifier(FrameReplyAIConnectionConsent(connection: connection))
    }

    private var providerHeader: some View {
        HStack(spacing: 0) {
            if subscribed {
                Button {
                    if !isSelected { connection.requestConnection() }
                } label: {
                    providerLabel
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Use FrameReply AI")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityIdentifier("ai-access-connect")
            } else {
                providerLabel
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }

            Menu {
                supportActions
            } label: {
                ProviderOptionsIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("FrameReply AI options")
        }
        .padding(.trailing, 6)
    }

    private var providerLabel: some View {
        HStack(spacing: 12) {
            ProviderIcon(symbolName: "sparkles")
            VStack(alignment: .leading, spacing: 2) {
                Text("FrameReply AI")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineLimit(2)
                Text("AI replies, ready to go.")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ProviderSelectionIndicator(isActive: isSelected)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.leading, 16)
        .contentShape(Rectangle())
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
        case .notOffered:
            Text(
                "Subscription unavailable for this App Store account. You can use your own API key."
            )
            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        case .failed:
            HStack {
                Text("Couldn’t load subscription. Try again.")
                Button("Retry") { connection.refresh() }
                    .disabled(busy)
            }
        }
    }

    private var subscribeButton: some View {
        Button("Subscribe", action: connection.purchase)
            .controlSize(.large)
            .modifier(FrameReplyAIActionStyle())
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
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
    }

    private var subscriberDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            FrameReplyAISubscriptionStatus(isTrial: access.entitlement?.period.kind == "trial")
            if let usage = access.usage,
                let fraction = AIAccessPresentation.remainingFraction(usage)
            {
                Text(usage.kind == "trial" ? "Trial AI allowance" : "AI allowance")
                    .fontWeight(.semibold)
                ProgressView(value: fraction)
                    .tint(
                        AIAccessPresentation.usageLevel(fraction) == .available
                            ? FrameReplyColor.primary : .orange
                    )
                    .accessibilityLabel("AI allowance remaining")
                    .accessibilityValue(usageLabel(fraction))
                Text(usageLabel(fraction))
                if fraction == 0 {
                    Text("You can switch to a provider using your own API key.")
                }
            } else {
                Text("Current usage is temporarily unavailable.")
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
    }

    @ViewBuilder private var supportActions: some View {
        Button("Restore Purchases", action: connection.restore)
            .disabled(busy || access.configuration == nil)
            .accessibilityIdentifier("ai-access-restore")
        Button("Refresh Status") {
            connection.refresh()
        }
        .disabled(busy || access.configuration == nil)
    }

    private func usageLabel(_ fraction: Double) -> LocalizedStringKey {
        switch AIAccessPresentation.usageLevel(fraction) {
        case .available: "Available"
        case .low: "Running low"
        case .exhausted: "Period limit reached"
        }
    }
}
