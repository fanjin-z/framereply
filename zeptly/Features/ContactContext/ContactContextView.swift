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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(RezplyColor.primary)
                            .frame(width: 46, height: 46)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.68))
                                    .shadow(color: RezplyColor.primaryContainer.opacity(0.12), radius: 18, x: 0, y: 10)
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("Back to inbox")

                    ContactProfileCard(chat: chat, subtitle: context.relationshipSubtitle)

                    AboutContactCard(
                        contactName: chat.name,
                        memories: $context.contactMemories
                    )

                    ContactContextInfoGrid(
                        currentInteractionGoal: $context.currentInteractionGoal,
                        preferredPersona: $context.preferredPersona
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
