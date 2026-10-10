import StoreKit
import SwiftUI

struct FrameReplyAIOnboardingCard: View {
    @ObservedObject var access: AIAccessModel
    @StateObject private var connection: FrameReplyAIConnectionModel

    private var busy: Bool { connection.isBusy }

    init(
        access: AIAccessModel,
        providerStore: ProviderStore,
        onConnected: @escaping () -> Void,
        onConnectionStateChanged: ((Bool) -> Void)? = nil
    ) {
        self.access = access
        _connection = StateObject(
            wrappedValue: FrameReplyAIConnectionModel(
                access: access,
                providerStore: providerStore,
                onConnected: onConnected,
                onConnectionStateChanged: onConnectionStateChanged
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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
                            Button("Retry") {
                                connection.refresh(
                                    refreshAppTransaction: access.configuration == nil
                                )
                            }
                            .disabled(busy)
                        } else if access.hasActiveSubscription {
                            subscriberRow
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
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .foregroundStyle(FrameReplyColor.onSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider-row-frameReplyAI")
        .modifier(FrameReplyAIConnectionConsent(connection: connection))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProviderIcon(symbolName: "sparkles")
            Text("FrameReply AI")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var purchaseRow: some View {
        switch access.productAvailability {
        case .loading:
            EmptyView()
        case .available:
            VStack(spacing: 8) {
                Button(action: connection.purchase) {
                    Text(
                        access.trialDuration != nil
                            ? LocalizedStringResource("Start Free Trial")
                            : LocalizedStringResource("Subscribe")
                    )
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .controlSize(.regular)
                .modifier(FrameReplyAIActionStyle())
                .disabled(busy || access.product == nil)
                .accessibilityIdentifier("ai-access-purchase")

                offerSummary
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

    private var offerSummary: some View {
        Group {
            if let product = access.product, let period = access.billingPeriod {
                if let trial = access.trialDuration {
                    Text("\(trial) free, then \(product.displayPrice) per \(period).")
                } else {
                    Text("\(product.displayPrice) per \(period).")
                }
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var subscriberRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            FrameReplyAISubscriptionStatus(isTrial: access.entitlement?.period.kind == "trial")
            Button(action: connection.requestConnection) {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .controlSize(.regular)
            .modifier(FrameReplyAIActionStyle())
            .disabled(busy)
            .accessibilityIdentifier("continue-with-frame-reply-ai")
        }
    }
}
