import SwiftUI

struct ShortcutSetupView: View {
    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    guideSection(
                        title: "Image Shortcut",
                        symbol: "photo.on.rectangle.angled",
                        text:
                            "Share 1–8 screenshots or photos from one chat, or run the Shortcut to capture the screen."
                    )
                    guideSection(
                        title: "Text Shortcut",
                        symbol: "text.bubble",
                        text:
                            "Share selected message text when supported, or copy messages and run the Shortcut."
                    )
                    guideSection(
                        title: "Ways to Run",
                        symbol: "bolt.fill",
                        text:
                            "Use the Share Sheet, Spotlight, Action button, Back Tap, Home Screen, Siri, or the Shortcuts app."
                    )
                    guideSection(
                        title: "Before You Start",
                        symbol: "checkmark.circle",
                        text:
                            "Connect an active provider and allow provider sharing in Zeptly. If a Shortcut reports that consent is required, open Settings → Privacy & Data."
                    )
                    guideSection(
                        title: "Data Handling",
                        symbol: "hand.raised",
                        text:
                            "Selected content is sent to the active provider. Source images are discarded after processing; extracted messages are stored in Zeptly’s protected local database."
                    )
                }
                .padding(24)
                .padding(.bottom, 24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Shortcut Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guideSection(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.42))
    }
}
