//
//  ChatCaptureControls.swift
//  zeptly
//

import SwiftUI

struct ChatCaptureControls: View {
    let isScreenshotAttached: Bool
    let hasContextNote: Bool
    let onAttachTap: () -> Void
    let onContextTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onAttachTap()
            } label: {
                HStack(spacing: 9) {
                    Image(
                        systemName: isScreenshotAttached
                            ? "checkmark.circle" : "camera.badge.ellipsis"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    Text(isScreenshotAttached ? "Screenshot Added" : "Attach Screenshot")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(RezplyColor.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.secondaryContainer.opacity(0.42))
                }
            }
            .buttonStyle(SoftPressButtonStyle())

            Button {
                onContextTap()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: hasContextNote ? "checkmark.bubble" : "text.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(hasContextNote ? "Context Added" : "Add Context")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.primary)
                        .shadow(
                            color: RezplyColor.primaryContainer.opacity(0.28), radius: 18, x: 0,
                            y: 10)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
        }
    }
}
