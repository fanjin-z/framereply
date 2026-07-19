//
//  AvatarMark.swift
//  FrameReply
//

import SwiftUI

struct AvatarMark: View {
    let initials: String
    let symbolName: String?
    let colors: [Color]
    var size: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.72), lineWidth: 2)
                }
                .shadow(color: FrameReplyColor.primaryContainer.opacity(0.22), radius: 14, x: 0, y: 8)
                .overlay {
                    if let symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: size * 0.36, weight: .medium))
                            .foregroundStyle(FrameReplyColor.primary)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(
                                color: FrameReplyColor.deepNavy.opacity(0.32), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
