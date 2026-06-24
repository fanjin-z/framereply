//
//  EmptySearchState.swift
//  zeptly
//

import SwiftUI

struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .light))
            Text("No chats found")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(RezplyColor.outline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .glassPanel(cornerRadius: 26)
    }
}
