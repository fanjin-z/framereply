import SwiftUI

struct ScreenshotImportStatusCard: View {
    let symbolName: String
    let message: String
    let isLoading: Bool
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary)
            }

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let onCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint(
                        "Stops the current import or reply generation."
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
    }
}
