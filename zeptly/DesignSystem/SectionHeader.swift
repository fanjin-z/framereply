//
//  SectionHeader.swift
//  zeptly
//

import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let symbolName: String
    let title: String
    @ViewBuilder let trailing: Trailing

    init(symbolName: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbolName = symbolName
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RezplyColor.primary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 12)

            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(symbolName: String, title: String) {
        self.init(symbolName: symbolName, title: title) {
            EmptyView()
        }
    }
}
