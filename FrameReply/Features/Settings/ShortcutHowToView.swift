import AVKit
import Combine
import SwiftUI

struct ShortcutHowToRoute: Identifiable {
    enum ID: String {
        case share
        case copy
    }

    let id: ID
    let title: LocalizedStringResource
    let instruction: LocalizedStringResource
    let systemImage: String
}

enum ShortcutHowToKind: String, CaseIterable, Identifiable {
    case images
    case text

    var id: Self { self }

    var pickerTitle: LocalizedStringResource {
        switch self {
        case .images: "Images"
        case .text: "Copied Text"
        }
    }

    var mediaResourceName: String {
        switch self {
        case .images: "ShortcutImagesHowTo"
        case .text: "ShortcutTextHowTo"
        }
    }

    var quickSteps: [LocalizedStringResource] {
        switch self {
        case .images:
            [
                "Take screenshots of the conversation.",
                "Tap the screenshot preview, tap Share, then choose FrameReply Images."
            ]
        case .text:
            [
                "Select messages."
            ]
        }
    }

    var routes: [ShortcutHowToRoute] {
        switch self {
        case .images: []
        case .text:
            [
                ShortcutHowToRoute(
                    id: .share,
                    title: "Share",
                    instruction: "Tap Share, then choose FrameReply Text.",
                    systemImage: "square.and.arrow.up"
                ),
                ShortcutHowToRoute(
                    id: .copy,
                    title: "Copy",
                    instruction:
                        "Tap Copy. Go to the Home Screen, swipe down, then search FrameReply Text.",
                    systemImage: "doc.on.clipboard"
                )
            ]
        }
    }

    var tip: LocalizedStringResource? {
        switch self {
        case .images: nil
        case .text: "If the messages don’t include sender names, use screenshots instead."
        }
    }
}

struct ShortcutHowToView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: ShortcutHowToKind = .images

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        guidePicker
                        ShortcutHowToMediaView(kind: selectedKind)
                            .id(selectedKind)
                        quickSteps
                        completionNote

                        if let tip = selectedKind.tip {
                            helpTip(tip)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Using Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("dismiss-shortcut-how-to")
                }
            }
        }
        .accessibilityIdentifier("shortcut-how-to-screen")
    }

    private var guidePicker: some View {
        Picker("Shortcut guide", selection: $selectedKind) {
            ForEach(ShortcutHowToKind.allCases) { kind in
                Text(kind.pickerTitle).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("shortcut-how-to-picker")
    }

    private var quickSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick steps")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

            VStack(spacing: 0) {
                ForEach(Array(selectedKind.quickSteps.enumerated()), id: \.offset) { entry in
                    numberedStep(entry.element, number: entry.offset + 1)

                    if entry.offset < selectedKind.quickSteps.count - 1
                        || !selectedKind.routes.isEmpty
                    {
                        stepDivider
                    }
                }

                if !selectedKind.routes.isEmpty {
                    routeChoices(number: selectedKind.quickSteps.count + 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.46))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("shortcut-how-to-steps")
        }
    }

    private func numberedStep(
        _ text: LocalizedStringResource,
        number: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number)

            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func routeChoices(number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(selectedKind.routes.enumerated()), id: \.offset) { entry in
                    routeRow(entry.element)

                    if entry.offset < selectedKind.routes.count - 1 {
                        Divider()
                            .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
                            .padding(.leading, 36)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func routeRow(_ route: ShortcutHowToRoute) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: route.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(FrameReplyColor.primaryFixed.opacity(0.62))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Text(route.instruction)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FrameReplyColor.onSurface)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(FrameReplyColor.primary)
            .frame(width: 24, height: 24)
            .background {
                Circle().fill(FrameReplyColor.primaryFixed.opacity(0.82))
            }
    }

    private var stepDivider: some View {
        Divider()
            .overlay(FrameReplyColor.outlineVariant.opacity(0.5))
            .padding(.leading, 50)
    }

    private func helpTip(_ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FrameReplyColor.surfaceContainerHigh.opacity(0.72))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shortcut-text-sender-label-tip")
    }

    private var completionNote: some View {
        Label(
            "Use Reply copies it. Paste it in your chat.",
            systemImage: "doc.on.doc"
        )
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("shortcut-use-reply-note")
    }
}

private struct ShortcutHowToMediaView: View {
    @Environment(\.scenePhase) private var scenePhase

    let kind: ShortcutHowToKind

    @StateObject private var playerModel: ShortcutHowToMediaPlayerModel

    init(kind: ShortcutHowToKind) {
        self.kind = kind
        _playerModel = StateObject(
            wrappedValue: ShortcutHowToMediaPlayerModel(
                resourceName: kind.mediaResourceName
            )
        )
    }

    var body: some View {
        VideoPlayer(player: playerModel.player)
            .background(Color.black)
            .frame(width: 180, height: 370)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FrameReplyColor.outlineVariant.opacity(0.45), lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("shortcut-how-to-media-\(kind.rawValue)")
            .onAppear {
                guard scenePhase == .active else { return }
                playerModel.play()
            }
            .onDisappear {
                playerModel.pause()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    playerModel.play()
                } else {
                    playerModel.pause()
                }
            }
    }
}

@MainActor
final class ShortcutHowToMediaPlayerModel: ObservableObject {
    let player: AVQueuePlayer

    private let playerLooper: AVPlayerLooper

    init(resourceName: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: resourceName, withExtension: "mp4") else {
            preconditionFailure("Missing bundled shortcut walkthrough: \(resourceName).mp4")
        }

        let player = AVQueuePlayer()
        self.player = player
        playerLooper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: url)
        )
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}
