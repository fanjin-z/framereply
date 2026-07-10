//
//  InboxView.swift
//  zeptly
//

import SwiftData
import SwiftUI
import PhotosUI

struct InboxView: View {
    let isActive: Bool
    let onChatTap: (Chat) -> Void
    let onAvatarTap: (Chat) -> Void
    let onImportCompleted: (String) -> Void
    @State private var searchText = ""
    @State private var isReviewPresented = false
    @State private var chatPendingDeletion: Chat?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteErrorMessage: String?
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []
    @State private var photoLoadErrorMessage: String?
    @StateObject private var importModel: InAppScreenshotImportViewModel
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chatRecords: [ChatRecord]
    @Query(filter: #Predicate<ChatMessageRecord> { $0.senderKind == "unknown" })
    private var unknownSenderMessages: [ChatMessageRecord]

    init(
        isActive: Bool,
        providerStore: ProviderStore,
        onChatTap: @escaping (Chat) -> Void,
        onAvatarTap: @escaping (Chat) -> Void,
        onImportCompleted: @escaping (String) -> Void
    ) {
        self.isActive = isActive
        self.onChatTap = onChatTap
        self.onAvatarTap = onAvatarTap
        self.onImportCompleted = onImportCompleted
        _importModel = StateObject(
            wrappedValue: InAppScreenshotImportViewModel(providerStore: providerStore)
        )
    }

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
                    screenshotSelection: $selectedScreenshotItems,
                    isSearchActive: isActive,
                    isImporting: importModel.isLoading
                )
                    .padding(.top, reviewCount > 0 ? 4 : 14)

                if let importErrorMessage {
                    InboxImportErrorMessage(message: importErrorMessage)
                }

                VStack(spacing: 16) {
                    ForEach(chats) { chat in
                        ChatRow(
                            chat: chat,
                            onChatTap: {
                                onChatTap(chat)
                            },
                            onAvatarTap: {
                                onAvatarTap(chat)
                            },
                            onDeleteTap: {
                                chatPendingDeletion = chat
                                isDeleteConfirmationPresented = true
                            }
                        )
                    }

                    if chats.isEmpty {
                        if chatRecords.isEmpty && searchText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty {
                            EmptyImportScreenshotsPicker(
                                selection: $selectedScreenshotItems,
                                isLoading: importModel.isLoading
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
            Text(deleteErrorMessage ?? "Try again.")
        }
        .onChange(of: selectedScreenshotItems) { _, items in
            Task {
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
            if let result = await importModel.importScreenshots(imageDataList) {
                onImportCompleted(result.chatID)
            }
        } catch {
            photoLoadErrorMessage = error.localizedDescription
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
                    .foregroundStyle(RezplyColor.primary.opacity(0.88))

                Text(text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(RezplyColor.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(RezplyColor.primary)
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.secondaryContainer.opacity(0.54))
                    }

                Spacer(minLength: 6)

                Text("Review")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        Capsule(style: .continuous)
                            .fill(RezplyColor.primary)
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
                            .fill(RezplyColor.surfaceContainerLow.opacity(0.42))
                    }
                    .overlay(alignment: .leading) {
                        if isAccented {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(RezplyColor.primary.opacity(0.56))
                                .frame(width: 3)
                                .padding(.vertical, 12)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(RezplyColor.outlineVariant.opacity(0.46), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(SoftPressButtonStyle())
    }
}

private struct InboxSearchImportRow: View {
    @Binding var searchText: String
    @Binding var screenshotSelection: [PhotosPickerItem]
    let isSearchActive: Bool
    let isImporting: Bool

    var body: some View {
        HStack(spacing: 10) {
            SearchField(text: $searchText, isActive: isSearchActive)
                .frame(maxWidth: .infinity)

            PhotosPicker(
                selection: $screenshotSelection,
                maxSelectionCount: 8,
                matching: .images
            ) {
                ZStack {
                    Circle()
                        .fill(RezplyColor.primary)
                        .shadow(
                            color: RezplyColor.primaryContainer.opacity(0.24),
                            radius: 14,
                            x: 0,
                            y: 8
                        )

                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .accessibilityLabel("Import screenshots")
        }
    }
}

private struct EmptyImportScreenshotsPicker: View {
    @Binding var selection: [PhotosPickerItem]
    let isLoading: Bool

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: 8,
            matching: .images
        ) {
            EmptyImportPrompt(isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct EmptyImportPrompt: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(RezplyColor.outline)

            Text("Import your first chat")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(RezplyColor.onSurface)

            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                }

                Text(isLoading ? "Importing Screenshots" : "Import Screenshots")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background {
                Capsule(style: .continuous)
                    .fill(RezplyColor.primary)
                    .shadow(
                        color: RezplyColor.primaryContainer.opacity(0.28),
                        radius: 16,
                        x: 0,
                        y: 9
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .glassPanel(cornerRadius: 26)
        .accessibilityLabel("Import screenshots")
    }
}

private struct InboxImportErrorMessage: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RezplyColor.peach)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RezplyColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
    }
}
