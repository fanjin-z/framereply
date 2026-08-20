import SwiftUI

struct ShortcutSetupSection: View {
    var showsHeader = true

    @State private var isBackTapGuidePresented = false
    @State private var isHowToUsePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack(spacing: 12) {
                    Text("Shortcuts")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                    Spacer()

                    Button {
                        isHowToUsePresented = true
                    } label: {
                        Label("How to Use", systemImage: "play.circle")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.primary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shortcut-how-to")
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 24)
            }

            VStack(spacing: 0) {
                shortcutRow(
                    title: "Image Shortcut",
                    subtitle: "Import screenshots",
                    symbol: "photo.on.rectangle.angled",
                    installation: ShortcutInstallationCatalog.images
                )

                divider

                shortcutRow(
                    title: "Text Shortcut",
                    subtitle: "Import copied messages",
                    symbol: "text.bubble",
                    installation: ShortcutInstallationCatalog.text
                )

                divider

                Button {
                    isBackTapGuidePresented = true
                } label: {
                    compactRow(
                        title: "Back Tap",
                        subtitle: "Double- or triple-tap the back of your iPhone to import screenshots",
                        symbol: "hand.tap",
                        trailing: AnyView(
                            Text("Set Up")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.primary)
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("set-up-back-tap")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.46))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .fullScreenCover(isPresented: $isBackTapGuidePresented) {
            BackTapGuideView()
        }
        .sheet(isPresented: $isHowToUsePresented) {
            ShortcutHowToView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func shortcutRow(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        symbol: String,
        installation: ShortcutInstallationDefinition
    ) -> some View {
        if let installationURL = installation.installationURL {
            Link(destination: installationURL) {
                compactRow(
                    title: title,
                    subtitle: subtitle,
                    symbol: symbol,
                    trailing: AnyView(
                        Text("Add")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.primary)
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(installation.title)")
        } else {
            compactRow(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                trailing: AnyView(
                    Text("Unavailable")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(FrameReplyColor.outline)
                )
            )
        }
    }

    private func compactRow(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        symbol: String,
        trailing: AnyView
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Divider()
            .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
            .padding(.leading, 60)
    }
}
