#if DEBUG
    import SwiftUI

    /// Internal diagnostics; these strings are deliberately excluded from the app's catalog.
    struct SandboxPurchaseDebugSection: View {
        @StateObject private var probe = SandboxPurchaseProbe()

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Sandbox Subscription · Debug")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        verbatim:
                            "Tests Apple Sandbox and backend verification. Does not enable Cloud AI access."
                    )
                    .font(.footnote)

                    if let configuration = probe.configuration {
                        Text(
                            verbatim:
                                "\(configuration.productID)\n\(configuration.baseURL.absoluteString)"
                        )
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack { controls }
                        VStack(alignment: .leading) { controls }
                    }
                    .disabled(probe.isBusy || probe.configuration == nil)

                    if probe.isBusy {
                        ProgressView()
                    }

                    Text(verbatim: probe.result)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
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
            .buttonStyle(.borderedProminent)

            Button {
                Task { await probe.run(.recheck) }
            } label: {
                Text(verbatim: "Recheck purchase")
            }
            .buttonStyle(.bordered)
        }
    }
#endif
