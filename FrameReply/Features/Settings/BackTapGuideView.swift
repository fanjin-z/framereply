import SwiftUI

struct BackTapGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var backTapTutorial = BackTapTutorialPlayerModel()
    @State private var isOpeningShortcutInstaller = false

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        imageShortcutPrerequisite
                        setupSteps
                        inlineVideo
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Set Up Back Tap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismissGuide)
                        .accessibilityIdentifier("dismiss-back-tap-guide")
                }
            }
        }
        .accessibilityIdentifier("back-tap-guide-screen")
        .onDisappear {
            backTapTutorial.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, isOpeningShortcutInstaller else { return }
            isOpeningShortcutInstaller = false
            backTapTutorial.resumeAfterExternalNavigation()
        }
    }

    @ViewBuilder
    private var imageShortcutPrerequisite: some View {
        if let installationURL = ShortcutInstallationCatalog.images.installationURL {
            Button {
                openShortcutInstaller(installationURL)
            } label: {
                imageShortcutPrerequisiteContent(
                    trailingTitle: "Add",
                    isAvailable: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add FrameReply Images")
            .accessibilityHint("Opens the shortcut installer")
            .accessibilityIdentifier("add-image-shortcut-from-back-tap-guide")
        } else {
            imageShortcutPrerequisiteContent(
                trailingTitle: "Unavailable",
                isAvailable: false
            )
        }
    }

    private func imageShortcutPrerequisiteContent(
        trailingTitle: LocalizedStringResource,
        isAvailable: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.56))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("FrameReply Images")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text("Required for Back Tap setup")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            Text(trailingTitle)
                .font(
                    .system(
                        size: isAvailable ? 13 : 11,
                        weight: isAvailable ? .bold : .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    isAvailable ? FrameReplyColor.primary : FrameReplyColor.outline
                )
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FrameReplyColor.primaryFixed.opacity(0.68))
        }
    }

    private var setupSteps: some View {
        VStack(spacing: 0) {
            setupStep(
                number: 1,
                title: Text("Open iPhone **Settings**"),
                titleWeight: .regular
            )
            divider
            setupStep(
                number: 2,
                title: Text("Accessibility → Touch → Back Tap")
            )
            divider
            setupStep(
                number: 3,
                title: Text(
                    "Choose **Double Tap** or **Triple Tap**, then select **FrameReply Images**."
                ),
                titleWeight: .regular
            )
            divider
            setupStep(
                number: 4,
                title: Text("Turn Off **Show Banner**"),
                titleWeight: .regular,
                detail: "Prevents it from covering screenshots."
            )
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.46))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func setupStep(
        number: Int,
        title: Text,
        titleWeight: Font.Weight = .bold,
        detail: LocalizedStringResource? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(FrameReplyColor.primary)
                }

            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.system(size: 14, weight: titleWeight, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)

                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider()
            .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
            .padding(.leading, 40)
    }

    private var inlineVideo: some View {
        BackTapTutorialSourceView(model: backTapTutorial)
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .onAppear {
                backTapTutorial.play()
            }
    }

    private func dismissGuide() {
        backTapTutorial.stop()
        dismiss()
    }

    private func openShortcutInstaller(_ installationURL: URL) {
        isOpeningShortcutInstaller = true
        backTapTutorial.pauseForExternalNavigation()

        openURL(installationURL) { didOpen in
            guard didOpen == false else { return }

            Task { @MainActor in
                isOpeningShortcutInstaller = false
                backTapTutorial.resumeAfterExternalNavigation()
            }
        }
    }
}
