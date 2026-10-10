import SwiftUI

struct FrameReplyAIConnectionConsent: ViewModifier {
    let connection: FrameReplyAIConnectionModel
    @State private var isConsentPresented = false
    @State private var consent: ManagedAIConsent?

    func body(content: Content) -> some View {
        content
            .onReceive(connection.consentRequested) { disclosure in
                consent = disclosure
                isConsentPresented = true
            }
            .alert(
                "Share content to generate replies?", isPresented: $isConsentPresented
            ) {
                Button("Not Now", role: .cancel) {}
                Button("Allow & Connect") {
                    if let consent { connection.allowConnection(consent) }
                }
            } message: {
                Text(consent?.permissionMessage ?? "")
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
