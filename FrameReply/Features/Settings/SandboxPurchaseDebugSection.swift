#if DEBUG
    import SwiftUI

    /// Internal diagnostics; these strings are deliberately excluded from the app's catalog.
    struct SandboxPurchaseDebugSection: View {
        @StateObject private var probe = SandboxPurchaseProbe()
        @ObservedObject private var transactionObserver = SubscriptionTransactionObserver.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Sandbox Authentication & Subscription · Debug")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        verbatim:
                            "Test app authentication without a purchase, then verify Apple Sandbox subscriptions. Does not enable AI access."
                    )
                    .font(.footnote)

                    if let configuration = probe.configuration {
                        Text(
                            verbatim:
                                "\(configuration.baseURL.absoluteString)\nApp Attest: \(configuration.appAttestEnvironment)\nProduct: \(configuration.productID.isEmpty ? "Not configured" : configuration.productID)"
                        )
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }

                    Button {
                        Task { await probe.run(.authenticate) }
                    } label: {
                        Text(verbatim: "Test authentication")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(probe.isBusy || probe.configuration == nil)

                    ViewThatFits(in: .horizontal) {
                        HStack { controls }
                        VStack(alignment: .leading) { controls }
                    }
                    .disabled(probe.isBusy || probe.configuration?.productID.isEmpty != false)

                    if probe.isBusy {
                        ProgressView()
                    }

                    Text(verbatim: probe.result)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)

                    if let update = transactionObserver.lastResult {
                        Text(verbatim: update)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .foregroundStyle(FrameReplyColor.onSurface)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 18))
            }
        }

        @ViewBuilder
        private var controls: some View {
            Button {
                Task { await probe.run(.buy) }
            } label: {
                Text(verbatim: "Buy and verify")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await probe.run(.recheck) }
            } label: {
                Text(verbatim: "Recheck purchase")
            }
            .buttonStyle(.bordered)
        }
    }
#endif
