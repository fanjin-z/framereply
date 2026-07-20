//
//  PillChip.swift
//  FrameReply
//

import SwiftUI

struct PillChip: View {
    let title: LocalizedStringResource
    var symbolName: String?
    var tint: Color = FrameReplyColor.primary

    var body: some View {
        HStack(spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                }
        }
    }
}
