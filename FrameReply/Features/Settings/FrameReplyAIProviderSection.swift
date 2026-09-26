import SwiftUI

/// Resolves Apple's verified environment before creating the subscription client.
struct FrameReplyAIProviderSection: View {
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool
    @State private var configuration: SubscriptionConfiguration?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let configuration {
                FrameReplyAIProviderCard(
                    configuration: configuration, providerStore: providerStore, isActive: isActive)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FrameReply AI").font(.headline)
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Subscription status is temporarily unavailable.")
                            .font(.footnote)
                        Button("Retry") { Task { await load(refreshAppTransaction: true) } }
                    }
                }
                .padding(16)
            }
        }
        .task(id: isActive) {
            if isActive, configuration == nil { await load() }
        }
    }

    private func load(refreshAppTransaction: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        configuration = try? await SubscriptionConfiguration.load(
            refreshAppTransaction: refreshAppTransaction)
    }
}
