import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

struct BackTapTutorialSourceView: View {
    @ObservedObject var model: BackTapTutorialPlayerModel

    var body: some View {
        Group {
            if model.hasTutorialAsset {
                BackTapPlayerLayerView(model: model)
            } else {
                BackTapTutorialFallbackView()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FrameReplyColor.outlineVariant.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: FrameReplyColor.deepNavy.opacity(0.14), radius: 16, y: 8)
        .accessibilityIdentifier("back-tap-tutorial-video")
    }
}

@MainActor
final class BackTapTutorialPlayerModel: NSObject, ObservableObject {
    @Published private(set) var isPictureInPictureActive = false

    let player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var pictureInPictureController: AVPictureInPictureController?

    var hasTutorialAsset: Bool {
        player != nil
    }

    override init() {
        if let url = Bundle.main.url(forResource: "BackTapTutorial", withExtension: "mp4") {
            let queuePlayer = AVQueuePlayer()
            let item = AVPlayerItem(url: url)
            player = queuePlayer
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            player = nil
        }
        super.init()
    }

    func attach(to playerLayer: AVPlayerLayer) {
        guard let player else { return }
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            return
        }
        controller.delegate = self
        pictureInPictureController = controller
    }

    func play() {
        guard let player else { return }
        configureAudioSession()
        player.play()
    }

    func startPictureInPictureWhenPossible() async {
        for _ in 0..<10 {
            guard Task.isCancelled == false else { return }
            if pictureInPictureController?.isPictureInPicturePossible == true {
                startPictureInPicture()
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func startPictureInPicture() {
        guard
            let pictureInPictureController,
            pictureInPictureController.isPictureInPicturePossible,
            pictureInPictureController.isPictureInPictureActive == false
        else {
            return
        }
        pictureInPictureController.startPictureInPicture()
    }

    func stop() {
        if pictureInPictureController?.isPictureInPictureActive == true {
            pictureInPictureController?.stopPictureInPicture()
        }
        player?.pause()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
        try? session.setActive(true)
    }
}

extension BackTapTutorialPlayerModel: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPictureInPictureActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPictureInPictureActive = false
    }
}

private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct BackTapPlayerLayerView: UIViewRepresentable {
    @ObservedObject var model: BackTapTutorialPlayerModel

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        model.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

private struct BackTapTutorialFallbackView: View {
    private let steps: [(String, String)] = [
        ("accessibility", "Accessibility"),
        ("hand.tap", "Touch"),
        ("iphone.radiowaves.left.and.right", "Back Tap"),
        ("bolt.fill", "FrameReply Images")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 7) {
                    Image(systemName: step.0)
                        .font(.system(size: 18, weight: .semibold))
                    Text(step.1)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(FrameReplyColor.onSurface)
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(FrameReplyColor.outline)
                }
            }
        }
        .padding(18)
        .background(FrameReplyColor.surfaceContainerLow)
    }
}
