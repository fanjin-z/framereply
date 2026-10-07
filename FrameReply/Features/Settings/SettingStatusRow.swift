//
//  SettingStatusRow.swift
//  FrameReply
//

import SwiftUI

struct SettingStatusRow<Value: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

            Spacer()

            value
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(FrameReplyColor.primary)
        }
    }
}
