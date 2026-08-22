//
//  ChatsView.swift
//  FrameReply
//

import PhotosUI
import SwiftData
import SwiftUI

struct ChatsView: View {
    let isActive: Bool
    let onChatTap: (Chat) -> Void
    let onImportCompleted: (String) -> Void
    private let chatRepository: ChatRepository
    private let personaRepository: PersonaRepository
    @State private var searchText = ""
    @State private var isReviewPresented = false
    @State private var isImportSourcePresented = false
    @State private var chatToDelete: Chat?
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
        chatRepository: ChatRepository,
        personaRepository: PersonaRepository,
        onChatTap: @escaping (Chat) -> Void,
        onImportCompleted: @escaping (String) -> Void
    ) {
        self.isActive = isActive
        self.chatRepository = chatRepository
        self.personaRepository = personaRepository
        self.onChatTap = onChatTap
        self.onImportCompleted = onImportCompleted
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(
                providerStore: providerStore,
                repository: chatRepository
            )
        )
    }

    private var chats: [ChatCardItem] {
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
            (try? personaRepository.defaultPersona())?.value
            ?? personaRecords.first?.value
        let allChats = chatRecords.compactMap { record -> ChatCardItem? in
            let interpretation = ProvisionalIdentityResolver.resolve(
                chat: record,
                messages: unknownSenderMessages.filter { $0.chatID == record.id },
                previouslyUsedSelfAliasLabels: usedSelfAliasLabels
            )
            let chat = Chat(record: record, provisionalIdentity: interpretation)
            guard
                let persona = ChatsPresentation.persona(
                    context: contextsByChatID[record.id],
                    personasByID: personasByID,
                    fallback: defaultPersona
                )
            else {
                return nil
            }
            return ChatCardItem(chat: chat, persona: persona)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return allChats
        }

        return allChats.filter { item in
            ChatsPresentation.matches(
                query: query,
                chat: item.chat,
                persona: item.persona
            )
        }
    }

    var body: some View {
        List {
            let visibleChats = chats

            ChatsSearchImportRow(
                searchText: $searchText,
                isSearchActive: isActive,
                isImporting: importModel.isLoading,
                onImportTap: {
                    isImportSourcePresented = true
                }
            )
            .listRowInsets(EdgeInsets(top: 14, leading: 24, bottom: 6, trailing: 24))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if reviewCount > 0 {
                ChatsImportReviewNudge(
                    text: reviewNudgeText,
                    iconName: reviewNudgeIconName,
                    count: reviewCount,
                    isAccented: hasUnknownSenderReview,
                    onTap: {
                        isReviewPresented = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let importErrorMessage {
                ChatsImportErrorMessage(
                    message: importErrorMessage,
                    onDismiss: dismissImportError
                )
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if visibleChats.isEmpty {
                let isSearchEmpty = searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                Group {
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
                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(Array(visibleChats.enumerated()), id: \.element.id) { index, item in
                    ChatCard(
                        chat: item.chat,
                        persona: item.persona,
                        onChatTap: {
                            onChatTap(item.chat)
                        }
                    )
                    .contextMenu {
                        Button("Delete Chat", systemImage: "trash", role: .destructive) {
                            chatToDelete = item.chat
                        }
                    }
                    .accessibilityAction(named: "Delete Chat") {
                        chatToDelete = item.chat
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            chatToDelete = item.chat
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("chat-delete-\(item.id)")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(chatListRowBackground)
                    .listRowSeparator(
                        index < visibleChats.count - 1 ? .visible : .hidden,
                        edges: .bottom
                    )
                    .listRowSeparatorTint(FrameReplyColor.outlineVariant.opacity(0.42))
                }
            }

            Color.clear
                .frame(height: 94)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("chats-screen")
        .sheet(isPresented: $isReviewPresented) {
            ChatImportReviewSheet(repository: chatRepository)
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
            "Delete chat with \(chatToDelete?.name ?? "this person")?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: chatToDelete
        ) { chat in
            Button("Delete Chat", role: .destructive) {
                deleteChat(chat)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
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

    private var chatListRowBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.white.opacity(0.48))
    }

    private var reviewCount: Int {
        let provisionalIDs = Set(chatRecords.filter(\.requiresImportReview).map(\.id))
        let unknownIDs = Set(unknownSenderMessages.map(\.chatID))
        return provisionalIDs.union(unknownIDs).count
    }

    private var hasProvisionalImportReview: Bool {
        chatRecords.contains { $0.requiresImportReview }
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

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { chatToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    chatToDelete = nil
                }
            }
        )
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

    private func dismissImportError() {
        photoLoadErrorMessage = nil
        importModel.dismissError()
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

    private func deleteChat(_ chat: Chat) {
        do {
            try chatRepository.deleteChat(id: chat.id)
            chatToDelete = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

struct ChatCardItem: Identifiable {
    let chat: Chat
    let persona: Persona

    var id: String { chat.id }
}

enum ChatsPresentation {
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
        chat.requiresImportReview ? .reviewImport : .persona(persona)
    }

    static func matches(query: String, chat: Chat, persona: Persona) -> Bool {
        let matchesReview =
            chat.requiresImportReview
            && String(localized: "Review Import").localizedCaseInsensitiveContains(query)
        return chat.name.localizedCaseInsensitiveContains(query)
            || chat.preview.localizedCaseInsensitiveContains(query)
            || persona.name.localizedCaseInsensitiveContains(query)
            || matchesReview
    }
}

private struct ChatsImportReviewNudge: View {
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

private struct ChatsSearchImportRow: View {
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
                            color: FrameReplyColor.primaryContainer.opacity(0.18),
                            radius: 10,
                            x: 0,
                            y: 6
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
                .frame(width: 44, height: 44)
            }
            .buttonStyle(SoftPressButtonStyle())
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
        .padding(.vertical, 28)
        .glassPanel(cornerRadius: 26)
        .accessibilityLabel("Add messages")
        .accessibilityIdentifier("add-messages")
    }
}

private struct ChatsImportErrorMessage: View {
    let message: String
    let onDismiss: () -> Void

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
        .padding(.trailing, 16)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
        .overlay(alignment: .topTrailing) {
            ScreenshotImportDismissButton(action: onDismiss)
                .padding(.top, 2)
                .padding(.trailing, 4)
        }
    }
}
