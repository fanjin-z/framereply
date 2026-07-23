//
//  InboxView.swift
//  FrameReply
//

import PhotosUI
import SwiftData
import SwiftUI

struct InboxView: View {
    let isActive: Bool
    let onChatTap: (Chat) -> Void
    let onImportCompleted: (String) -> Void
    @State private var searchText = ""
    @State private var isReviewPresented = false
    @State private var isImportSourcePresented = false
    @State private var chatPendingDeletion: Chat?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteErrorMessage: String?
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []
    @State private var photoLoadErrorMessage: String?
    @State private var importDraftingInput = ""
    @State private var importTask: Task<Void, Never>?
    @StateObject private var importModel: InAppScreenshotImportViewModel
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chatRecords: [ChatRecord]
    @Query private var chatContextRecords: [ChatContextRecord]
    @Query(sort: \PersonaRecord.createdAt) private var personaRecords: [PersonaRecord]
    @Query(filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" })
    private var unknownSenderMessages: [ChatMessageRecord]

    init(
        isActive: Bool,
        providerStore: ProviderStore,
        onChatTap: @escaping (Chat) -> Void,
        onImportCompleted: @escaping (String) -> Void
    ) {
        self.isActive = isActive
        self.onChatTap = onChatTap
        self.onImportCompleted = onImportCompleted
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(providerStore: providerStore)
        )
    }

    private var chats: [InboxChatCardItem] {
        let usedSelfAliasLabels =
            ProvisionalIdentityResolver.previouslyUsedSelfAliasLabels(
                in: chatContextRecords
            )
        let contextsByChatID = Dictionary(
            uniqueKeysWithValues: chatContextRecords.map { ($0.chatID, $0) }
        )
        let personasByID = Dictionary(
            uniqueKeysWithValues: personaRecords.map { ($0.id, $0.value) }
        )
        let defaultPersona =
            (try? PersonaRepository().defaultPersona())?.value
            ?? personaRecords.first?.value
        let allChats = chatRecords.compactMap { record -> InboxChatCardItem? in
            let interpretation = ProvisionalIdentityResolver.resolve(
                chat: record,
                messages: unknownSenderMessages.filter { $0.chatID == record.id },
                previouslyUsedSelfAliasLabels: usedSelfAliasLabels
            )
            let chat = Chat(record: record, provisionalIdentity: interpretation)
            guard
                let persona = InboxChatPresentation.persona(
                    context: contextsByChatID[record.id],
                    personasByID: personasByID,
                    fallback: defaultPersona
                )
            else {
                return nil
            }
            return InboxChatCardItem(chat: chat, persona: persona)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return allChats
        }

        return allChats.filter { item in
            InboxChatPresentation.matches(
                query: query,
                chat: item.chat,
                persona: item.persona
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if reviewCount > 0 {
                    InboxImportReviewNudge(
                        text: reviewNudgeText,
                        iconName: reviewNudgeIconName,
                        count: reviewCount,
                        isAccented: hasUnknownSenderReview,
                        onTap: {
                            isReviewPresented = true
                        }
                    )
                    .padding(.top, 14)
                }

                InboxSearchImportRow(
                    searchText: $searchText,
                    isSearchActive: isActive,
                    isImporting: importModel.isLoading,
                    onImportTap: {
                        isImportSourcePresented = true
                    }
                )
                .padding(.top, reviewCount > 0 ? 4 : 14)

                if let importErrorMessage {
                    InboxImportErrorMessage(message: importErrorMessage)
                }

                if importModel.isLoading {
                    ScreenshotImportStatusCard(
                        symbolName: "sparkles",
                        message: importModel.phase == .analyzing
                            ? "Analyzing messages…"
                            : "Generating replies…",
                        isLoading: true,
                        onCancel: {
                            importTask?.cancel()
                        }
                    )
                }

                VStack(spacing: 16) {
                    ForEach(chats) { item in
                        InboxChatCard(
                            chat: item.chat,
                            persona: item.persona,
                            onChatTap: {
                                onChatTap(item.chat)
                            },
                            onDeleteTap: {
                                chatPendingDeletion = item.chat
                                isDeleteConfirmationPresented = true
                            }
                        )
                    }

                    if chats.isEmpty {
                        let isSearchEmpty = searchText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        if chatRecords.isEmpty && isSearchEmpty {
                            EmptyImportPrompt(
                                isLoading: importModel.isLoading,
                                onImportTap: {
                                    isImportSourcePresented = true
                                }
                            )
                        } else {
                            EmptySearchState()
                        }
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
        .sheet(isPresented: $isImportSourcePresented) {
            ChatImportSourceSheet(
                screenshotSelection: $selectedScreenshotItems,
                draftingInput: $importDraftingInput,
                onPaste: { items in
                    importTask?.cancel()
                    importTask = Task {
                        await importCopiedMessages(items)
                    }
                }
            )
        }
        .confirmationDialog(
            "Delete chat with \(chatPendingDeletion?.name ?? "this person")?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                deletePendingChat()
            }
            Button("Cancel") {
                chatPendingDeletion = nil
            }
        } message: {
            Text("This permanently deletes this chat and its data. This can’t be undone.")
        }
        .alert("Could Not Delete Chat", isPresented: deleteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: deleteErrorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
        .onChange(of: selectedScreenshotItems) { _, items in
            if !items.isEmpty {
                isImportSourcePresented = false
            }
            importTask?.cancel()
            importTask = Task {
                await importSelectedScreenshots(items)
            }
        }
    }

    private var reviewCount: Int {
        let provisionalIDs = Set(chatRecords.filter(\.isProvisional).map(\.id))
        let unknownIDs = Set(unknownSenderMessages.map(\.chatID))
        return provisionalIDs.union(unknownIDs).count
    }

    private var hasProvisionalImportReview: Bool {
        chatRecords.contains { $0.isProvisional }
    }

    private var hasUnknownSenderReview: Bool {
        !unknownSenderMessages.isEmpty
    }

    private var reviewNudgeText: String {
        hasUnknownSenderReview && !hasProvisionalImportReview ? "Review senders" : "Review imports"
    }

    private var reviewNudgeIconName: String {
        hasUnknownSenderReview ? "person.crop.circle.badge.questionmark" : "tray.and.arrow.down"
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private var importErrorMessage: String? {
        photoLoadErrorMessage ?? importModel.errorMessage
    }

    private func importSelectedScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { selectedScreenshotItems = [] }
        photoLoadErrorMessage = nil

        do {
            let imageDataList = try await ChatScreenshotPhotoLoader.loadData(from: items)
            if let result = await importModel.importScreenshots(
                imageDataList,
                draftingInput: importDraftingInput
            ) {
                if result.replies != nil {
                    importDraftingInput = ""
                }
                onImportCompleted(result.chatID)
            }
        } catch is CancellationError {
        } catch {
            photoLoadErrorMessage = error.localizedDescription
        }
    }

    private func importCopiedMessages(_ items: [String]) async {
        guard !items.isEmpty else { return }
        photoLoadErrorMessage = nil

        if let result = await importModel.importCopiedMessages(
            items,
            draftingInput: importDraftingInput
        ) {
            if result.replies != nil {
                importDraftingInput = ""
            }
            onImportCompleted(result.chatID)
        }
    }

    private func deletePendingChat() {
        guard let chat = chatPendingDeletion else {
            return
        }

        do {
            try ChatRepository().deleteChat(id: chat.id)
            chatPendingDeletion = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

struct InboxChatCardItem: Identifiable {
    let chat: Chat
    let persona: Persona

    var id: String { chat.id }
}

enum InboxChatPresentation {
    enum Badge: Equatable {
        case persona(Persona)
        case reviewImport
    }

    static func persona(
        context: ChatContextRecord?,
        personasByID: [UUID: Persona],
        fallback: Persona?
    ) -> Persona? {
        context.flatMap { personasByID[$0.personaID] } ?? fallback
    }

    static func badge(for chat: Chat, persona: Persona) -> Badge {
        chat.isProvisional ? .reviewImport : .persona(persona)
    }

    static func matches(query: String, chat: Chat, persona: Persona) -> Bool {
        let matchesReview =
            chat.isProvisional
            && String(localized: "Review Import").localizedCaseInsensitiveContains(query)
        return chat.name.localizedCaseInsensitiveContains(query)
            || chat.preview.localizedCaseInsensitiveContains(query)
            || persona.name.localizedCaseInsensitiveContains(query)
            || matchesReview
    }
}

private struct InboxImportReviewNudge: View {
    let text: String
    let iconName: String
    let count: Int
    let isAccented: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary.opacity(0.88))

                Text(text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.secondaryContainer.opacity(0.54))
                    }

                Spacer(minLength: 6)

                Text("Review")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FrameReplyColor.primary)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(FrameReplyColor.surfaceContainerLow.opacity(0.42))
                    }
                    .overlay(alignment: .leading) {
                        if isAccented {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(FrameReplyColor.primary.opacity(0.56))
                                .frame(width: 3)
                                .padding(.vertical, 12)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(FrameReplyColor.outlineVariant.opacity(0.46), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(SoftPressButtonStyle())
    }
}

private struct InboxSearchImportRow: View {
    @Binding var searchText: String
    let isSearchActive: Bool
    let isImporting: Bool
    let onImportTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SearchField(text: $searchText, isActive: isSearchActive)
                .frame(maxWidth: .infinity)

            Button(action: onImportTap) {
                ZStack {
                    Circle()
                        .fill(FrameReplyColor.primary)
                        .shadow(
                            color: FrameReplyColor.primaryContainer.opacity(0.24),
                            radius: 14,
                            x: 0,
                            y: 8
                        )

                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "text.below.photo")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .accessibilityLabel("Add messages")
            .accessibilityIdentifier("add-messages")
        }
    }
}

private struct EmptyImportPrompt: View {
    let isLoading: Bool
    let onImportTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(FrameReplyColor.outline)

            Text("Import your first chat")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

            Button(action: onImportTap) {
                HStack(spacing: 9) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "text.below.photo")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text(
                        isLoading
                            ? LocalizedStringResource("Importing Messages")
                            : LocalizedStringResource("Add Messages")
                    )
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background {
                    Capsule(style: .continuous)
                        .fill(FrameReplyColor.primary)
                        .shadow(
                            color: FrameReplyColor.primaryContainer.opacity(0.28),
                            radius: 16,
                            x: 0,
                            y: 9
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .glassPanel(cornerRadius: 26)
        .accessibilityLabel("Add messages")
        .accessibilityIdentifier("add-messages")
    }
}

private struct InboxImportErrorMessage: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FrameReplyColor.peach)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
    }
}
