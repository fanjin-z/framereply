//
//  ProfileButton.swift
//  zeptly
//

import SwiftUI

struct ProfileButton: View {
    let selectedTab: AppTab

    var body: some View {
        Button {
        } label: {
            if selectedTab == .settings {
                Circle()
                    .fill(RezplyColor.primaryContainer)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    }
            } else {
                AvatarMark(
                    initials: "R",
                    symbolName: nil,
                    colors: selectedTab == .personas
                        ? [RezplyColor.peach, RezplyColor.secondary]
                        : [RezplyColor.primaryContainer, RezplyColor.peach],
                    size: 36
                )
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }
}
