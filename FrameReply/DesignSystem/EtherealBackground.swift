//
//  EtherealBackground.swift
//  FrameReply
//

import SwiftUI

struct EtherealBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FrameReplyColor.surface,
                    FrameReplyColor.surfaceContainerLow,
                    FrameReplyColor.surfaceContainerHigh
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    FrameReplyColor.primaryContainer.opacity(0.22),
                    .clear,
                    FrameReplyColor.secondaryContainer.opacity(0.36)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blur(radius: 24)
        }
        .ignoresSafeArea()
    }
}
