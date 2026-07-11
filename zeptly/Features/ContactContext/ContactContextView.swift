//
//  ContactContextView.swift
//  zeptly
//

import SwiftUI

struct ContactContextView: View {
    let chat: Chat
    @Binding var context: ContactContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        Button {
                            KeyboardDismissal.dismiss()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(RezplyColor.primary)
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(SoftPressButtonStyle())
                        .accessibilityLabel("Back to inbox")

                        AvatarMark(
                            initials: chat.initials,
                            symbolName: chat.avatarSymbol,
                            colors: chat.gradient,
                            imageData: chat.avatarData,
                            size: 42
                        )

                        Text(chat.name)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 2)

                    AboutContactCard(
                        contactName: chat.name,
                        memories: $context.contactMemories
                    )

                    ContactContextInfoGrid(
                        currentInteractionGoal: $context.currentInteractionGoal,
                        personaID: $context.personaID,
                        personaAssignedAt: $context.personaAssignedAt
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
