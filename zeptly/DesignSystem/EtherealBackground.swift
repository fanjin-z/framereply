//
//  EtherealBackground.swift
//  zeptly
//

import SwiftUI

struct EtherealBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    RezplyColor.surface,
                    RezplyColor.surfaceContainerLow,
                    RezplyColor.surfaceContainerHigh
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    RezplyColor.primaryContainer.opacity(0.22),
                    .clear,
                    RezplyColor.secondaryContainer.opacity(0.36)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blur(radius: 24)
        }
        .ignoresSafeArea()
    }
}
