//
//  FactChip.swift
//  zeptly
//

import SwiftUI

struct FactChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(RezplyColor.onSurfaceVariant)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background {
                Capsule(style: .continuous)
                    .fill(RezplyColor.secondaryContainer.opacity(0.42))
                    .shadow(color: RezplyColor.primaryContainer.opacity(0.1), radius: 10, x: 0, y: 5)
            }
    }
}
