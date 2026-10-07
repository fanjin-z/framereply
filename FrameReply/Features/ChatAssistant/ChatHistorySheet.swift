//
//  ChatHistorySheet.swift
//  FrameReply
//

import SwiftData
import SwiftUI

enum ChatHistoryPresentation {
    static func matches(query: String, message: ChatMessage) -> Bool {
        message.text.localizedCaseInsensitiveContains(query)
            || message.timeLabel.localizedCaseInsensitiveContains(query)
            || message.groupParticipantName?.localizedCaseInsensitiveContains(query) == true
    }
}

struct ChatHistorySheet: View {
    let chat: Chat
    let provisionalIdentity: ProvisionalIdentityInterpretation?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedDetent: PresentationDetent = .large
    @Query private var messageRecords: [ChatMessageRecord]

    init(
        chat: Chat,
        provisionalIdentity: ProvisionalIdentityInterpretation? = nil
    ) {
        self.chat = chat
        self.provisionalIdentity = provisionalIdentity
        let chatID = chat.id
        _messageRecords = Query(
            filter: #Predicate<ChatMessageRecord> { $0.chatID == chatID },
            sort: \ChatMessageRecord.sortIndex
        )
    }

    private var messages: [ChatMessage] {
        messageRecords.map {
            ChatMessage(record: $0, provisionalIdentity: provisionalIdentity)
        }
    }

    private var filteredMessages: [ChatMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return messages
        }

        return messages.filter { message in
            ChatHistoryPresentation.matches(query: query, message: message)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                VStack(alignment: .leading, spacing: 18) {
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
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .scrollIndicators(.hidden)
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close chat history", systemImage: "xmark") {
                        KeyboardDismissal.dismiss()
                        dismiss()
                    }
                    .accessibilityIdentifier("close-chat-history")
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }
}
