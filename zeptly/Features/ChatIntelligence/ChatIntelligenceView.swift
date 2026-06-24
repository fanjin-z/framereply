//
//  ChatIntelligenceView.swift
//  zeptly
//

import SwiftUI

struct ChatIntelligenceView: View {
    let chat: Chat
    let intelligence: ChatIntelligence
    let onContactTap: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isHistoryPresented = false
    @State private var isContextPresented = false
    @State private var isScreenshotAttached = false
    @State private var contextNote = ""
    @State private var copiedReplyID: UUID?

    private var latestMessages: [ChatMessage] {
        Array(intelligence.messages.suffix(3))
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ChatIntelligenceTopBar(
                        chat: chat,
                        onBackTap: {
                            dismiss()
                        },
                        onContactTap: onContactTap
                    )

                    ChatContextChipPanel(chips: intelligence.contextChips)

                    RecentChatSection(
                        messages: latestMessages,
                        onSearchTap: {
                            isHistoryPresented = true
                        }
                    )

                    ChatCaptureControls(
                        isScreenshotAttached: isScreenshotAttached,
                        hasContextNote: !contextNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onAttachTap: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isScreenshotAttached.toggle()
                            }
                        },
                        onContextTap: {
                            isContextPresented = true
                        }
                    )

                    SuggestedRepliesSection(
                        replies: intelligence.suggestedReplies,
                        copiedReplyID: copiedReplyID,
                        onCopy: copyReply
                    )

                    SuggestedActionCard(action: intelligence.suggestedAction)

                    ChatReasoningCard(reasoning: intelligence.reasoning)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isHistoryPresented) {
            ChatHistorySheet(chat: chat, messages: intelligence.messages)
        }
        .sheet(isPresented: $isContextPresented) {
            AddChatContextSheet(note: $contextNote)
        }
    }

    private func copyReply(_ reply: SuggestedReply) {
        ClipboardWriter.copy(reply.text)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            copiedReplyID = reply.id
        }
    }
}
