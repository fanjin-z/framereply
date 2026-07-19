import SwiftUI

struct ProviderDataSharingDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let platform: ProviderPlatform

    private var disclosure: ProviderDataConsentDisclosure {
        ProviderDataConsentDisclosure(provider: platform)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        detailSection(
                            title: "Data shared",
                            text:
                                "Only the content you select: messages or screenshots, participant names, chat context, and drafts."
                        )
                        detailSection(
                            title: "Purpose",
                            text: "Analyze conversations and create suggested replies."
                        )
                        detailSection(
                            title: "Destination",
                            text: disclosure.destinationDescription
                        )
                        detailSection(
                            title: "Provider handling",
                            text:
                                "The provider may retain request data under its policy and may charge your provider account."
                        )
                        detailSection(
                            title: "FrameReply",
                            text:
                                "Requests go directly from this device to the provider. FrameReply operates no proxy server, analytics, advertising, or tracking."
                        )

                        Text("Only share content you have permission to use.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                        Link(
                            "Provider Privacy Policy",
                            destination: disclosure.privacyPolicyURL
                        )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
