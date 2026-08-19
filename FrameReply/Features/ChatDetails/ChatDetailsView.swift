//
//  ChatDetailsView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct ChatDetailsView: View {
    let chat: Chat
    private let repository: ChatRepository

    @Environment(\.dismiss) private var dismiss
    @Query private var chatRecords: [ChatRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query private var memoryRecords: [ChatMemoryRecord]
    @Query private var replyCaches: [SuggestedReplyCacheRecord]
    @State private var isForgetIdentityConfirmationPresented = false
    @State private var errorMessage: String?

    init(
        chat: Chat,
        repository: ChatRepository
    ) {
        self.chat = chat
        self.repository = repository
        let chatID = chat.id
        _chatRecords = Query(filter: #Predicate<ChatRecord> { $0.id == chatID })
        _chatContextRecords = Query(
            filter: #Predicate<ChatContextRecord> { $0.chatID == chatID }
        )
        _memoryRecords = Query(
            filter: #Predicate<ChatMemoryRecord> { $0.chatID == chatID },
            sort: \ChatMemoryRecord.createdAt
        )
        _replyCaches = Query(
            filter: #Predicate<SuggestedReplyCacheRecord> { $0.chatID == chatID }
        )
    }

    @MainActor private var displayedChat: Chat {
        chatRecords.first.map {
            Chat(record: $0)
        } ?? chat
    }

    private var rationale: String {
        replyCaches.first?.strategyRationale.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var selfAliasRecords: [SelfAliasRecord] {
        (chatContextRecords.first?.selfAliases ?? []).sorted {
            $0.displayLabel.localizedStandardCompare($1.displayLabel) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !rationale.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionHeader(
                                symbolName: "sparkles",
                                title: "Why These Replies"
                            )
                            .accessibilityElement(children: .combine)

                            StrategyRationaleCard(strategyRationale: rationale)
                        }
                    }

                    ChatMemoryCard(
                        chat: displayedChat,
                        memoryRecords: memoryRecords
                    )

                    if !selfAliasRecords.isEmpty {
                        selfAliasesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("chat-details-screen")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            backControl
        }
        .interactiveSwipeBackEnabled()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Forget these names for this chat?",
            isPresented: $isForgetIdentityConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Forget for This Chat", role: .destructive, action: forgetImportedIdentity)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Future imports into this chat may ask which sender is you again. Your saved names and existing messages won’t change."
            )
        }
        .alert("Could Not Update Chat", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var backControl: some View {
        HStack {
            FrameReplyTopBarBackButton(
                accessibilityLabel: "Back to chat assistant"
            ) {
                KeyboardDismissal.dismiss()
                dismiss()
            }
            .accessibilityIdentifier("chat-details-back")

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var selfAliasesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(
                symbolName: "person.text.rectangle",
                title: "You appear as"
            )
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                Text(selfAliasRecords.map(\.displayLabel).joined(separator: ", "))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "These names help recognize you in this chat and may be suggested for other imports."
                )
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Forget for this chat", role: .destructive) {
                        isForgetIdentityConfirmationPresented = true
                    }

                    Spacer(minLength: 8)

                    NavigationLink(value: FrameReplyRoute.personalInfo) {
                        HStack(spacing: 5) {
                            Text("Manage Personal Info")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(minHeight: 44)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 18)
        }
    }

    private func forgetImportedIdentity() {
        do {
            try repository.forgetImportedSelfLabels(chatID: chat.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
