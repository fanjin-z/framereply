//
//  ChatImportReviewSheet.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct ChatImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ChatRecord> { $0.isProvisional }) private var provisionalChats: [ChatRecord]
    @Query private var allChats: [ChatRecord]
    @State private var errorMessage: String?

    private var confirmedChats: [ChatRecord] {
        allChats.filter { !$0.isProvisional }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(provisionalChats) { chat in
                            ImportReviewCard(
                                chat: chat,
                                mergeCandidates: confirmedChats,
                                onConfirm: confirm,
                                onMerge: merge
                            )
                        }

                        if provisionalChats.isEmpty {
                            ContentUnavailableView(
                                "Imports Reviewed",
                                systemImage: "checkmark.bubble",
                                description: Text("There are no provisional chats waiting for review.")
                            )
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Review Imports")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Could Not Update Chat", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func confirm(chatID: String, name: String) {
        do {
            try ChatRepository().confirmProvisionalChat(chatID: chatID, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(provisionalChatID: String, targetChatID: String) {
        do {
            try ChatRepository().mergeProvisionalChat(provisionalChatID, into: targetChatID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportReviewCard: View {
    let chat: ChatRecord
    let mergeCandidates: [ChatRecord]
    let onConfirm: (String, String) -> Void
    let onMerge: (String, String) -> Void

    @State private var name: String

    init(
        chat: ChatRecord,
        mergeCandidates: [ChatRecord],
        onConfirm: @escaping (String, String) -> Void,
        onMerge: @escaping (String, String) -> Void
    ) {
        self.chat = chat
        self.mergeCandidates = mergeCandidates
        self.onConfirm = onConfirm
        self.onMerge = onMerge
        _name = State(initialValue: chat.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Needs review", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.primary)

            TextField("Chat name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text(chat.preview)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .lineLimit(3)

            HStack {
                Button("Keep as New") {
                    onConfirm(chat.id, name)
                }
                .buttonStyle(.borderedProminent)

                if !mergeCandidates.isEmpty {
                    Menu("Merge Into…") {
                        ForEach(mergeCandidates) { candidate in
                            Button(candidate.name) {
                                onMerge(chat.id, candidate.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 22)
    }
}
