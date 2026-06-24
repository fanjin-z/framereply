//
//  InboxView.swift
//  zeptly
//

import SwiftUI

struct InboxView: View {
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    @State private var searchText = ""

    private var chats: [Chat] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RezplySampleData.chats
        }

        return RezplySampleData.chats.filter { chat in
            chat.name.localizedCaseInsensitiveContains(searchText)
                || chat.preview.localizedCaseInsensitiveContains(searchText)
                || chat.chipTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SearchField(text: $searchText)
                    .padding(.top, 14)

                VStack(spacing: 16) {
                    ForEach(chats) { chat in
                        ChatRow(
                            chat: chat,
                            onChatTap: {
                                onChatTap(chat)
                            },
                            onAvatarTap: {
                                onAvatarTap(chat)
                            }
                        )
                    }

                    if chats.isEmpty {
                        EmptySearchState()
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 94)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}
