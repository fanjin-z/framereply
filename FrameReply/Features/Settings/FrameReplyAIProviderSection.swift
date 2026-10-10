import SwiftUI

/// Displays the app-owned subscription state after Apple's environment is resolved.
struct FrameReplyAIProviderSection: View {
    @ObservedObject var access: AIAccessModel
    @ObservedObject var providerStore: ProviderStore
    let isActive: Bool

    var body: some View {
        FrameReplyAIProviderCard(access: access, providerStore: providerStore)
            .task(id: isActive) {
                if isActive { await access.load() }
            }
    }
}
