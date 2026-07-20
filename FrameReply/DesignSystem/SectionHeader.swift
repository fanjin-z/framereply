//
//  SectionHeader.swift
//  FrameReply
//

import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let symbolName: String
    let title: LocalizedStringResource
    @ViewBuilder let trailing: Trailing

    init(
        symbolName: String,
        title: LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbolName = symbolName
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(symbolName: String, title: LocalizedStringResource) {
        self.init(symbolName: symbolName, title: title) {
            EmptyView()
        }
    }
}
