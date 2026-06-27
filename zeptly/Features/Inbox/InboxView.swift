//
//  InboxView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct InboxView: View {
    let isActive: Bool
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    @State private var searchText = ""
    @State private var isReviewPresented = false
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
                if provisionalCount > 0 {
                    Button {
                        isReviewPresented = true
                    } label: {
                        Label(
                            "Review \(provisionalCount) imported chat\(provisionalCount == 1 ? "" : "s")",
                            systemImage: "exclamationmark.bubble.fill"
                        )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(RezplyColor.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassPanel(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }

                SearchField(text: $searchText, isActive: isActive)
                    .padding(.top, provisionalCount > 0 ? 4 : 14)

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
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet()
        }
    }

    private var provisionalCount: Int {
        chatRecords.filter(\.isProvisional).count
    }
}
