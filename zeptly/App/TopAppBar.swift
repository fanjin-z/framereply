//
//  TopAppBar.swift
//  zeptly
//

import SwiftUI

struct TopAppBar: View {
    let selectedTab: AppTab

    var body: some View {
        HStack {
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(RezplyColor.primary)

            Spacer()

            Text("Rezply")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Spacer()

            ProfileButton(selectedTab: selectedTab)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(RezplyColor.surface.opacity(0.42))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.36))
                        .frame(height: 1)
                }
        }
    }
}
