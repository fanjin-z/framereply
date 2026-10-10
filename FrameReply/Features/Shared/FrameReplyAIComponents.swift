import SwiftUI

struct FrameReplyAIConnectionConsent: ViewModifier {
    @ObservedObject var connection: FrameReplyAIConnectionModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Share chat content with AI providers?", isPresented: $connection.isConsentPresented
            ) {
                Button("Not Now", role: .cancel) {}
                Button("Allow & Connect", action: connection.allowConnection)
            } message: {
                Text(ProviderDataConsentDisclosure(provider: .frameReplyAI).permissionMessage)
            }
    }
}

struct FrameReplyAIActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .tint(FrameReplyColor.actionFill)
            .foregroundStyle(.white)
    }
}

struct FrameReplyAISubscriptionStatus: View {
    let isTrial: Bool

    var body: some View {
        if isTrial {
            Text("Free trial active")
        } else {
            Text("Subscription active")
        }
    }
}
