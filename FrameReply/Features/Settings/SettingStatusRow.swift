//
//  SettingStatusRow.swift
//  FrameReply
//

import SwiftUI

struct SettingStatusRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            Spacer()

            value
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
        }
    }
}
