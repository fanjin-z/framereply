//
//  ChatHistorySheet.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatHistorySheet: View {
    let chat: Chat

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedDetent: PresentationDetent = .large
    @Query private var messageRecords: [ChatMessageRecord]

    init(chat: Chat) {
        self.chat = chat
        let chatID = chat.id
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
    }

    private var messages: [ChatMessage] {
        messageRecords.map { ChatMessage(record: $0) }
    }

    private var filteredMessages: [ChatMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return messages
        }

        return messages.filter { message in
            message.text.localizedCaseInsensitiveContains(query)
                || message.timeLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chat History")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurface)

                        Text(chat.name)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(RezplyColor.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(RezplyColor.primary)
                            .frame(width: 38, height: 38)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.72))
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("Close chat history")
                }

                SearchField(text: $searchText)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredMessages) { message in
                            ChatMessageBubble(message: message)
                        }

                        if filteredMessages.isEmpty {
                            EmptySearchState()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }
}
