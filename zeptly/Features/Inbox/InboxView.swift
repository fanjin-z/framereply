//
//  InboxView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct InboxView: View {
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    @State private var searchText = ""
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chatRecords: [ChatRecord]

    private var chats: [Chat] {
        let allChats = chatRecords.map { Chat(record: $0) }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allChats
        }

        return allChats.filter { chat in
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
