//
//  FrameReplyTopBar.swift
//  FrameReply
//

import SwiftUI

/// Keeps secondary-screen navigation visually distinct from the content it controls.
struct FrameReplyTopBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
            .frame(maxWidth: 768)
            .frame(maxWidth: .infinity)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        FrameReplyColor.surfaceContainerLow.opacity(0.72)
                    }
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FrameReplyColor.outlineVariant.opacity(0.34))
                    .frame(height: 1)
            }
            .shadow(
                color: FrameReplyColor.deepNavy.opacity(0.07),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

struct FrameReplyTopBarBackButton: View {
    let accessibilityLabel: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.62))
                }
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}
