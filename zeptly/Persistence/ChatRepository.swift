//
//  ChatRepository.swift
//  zeptly
//

import Foundation
import SwiftData

@MainActor
final class ChatRepository {
    private let context: ModelContext
    private let seedVersion = "2"
    private let seedVersionKey = "sampleSeedVersion"

    convenience init() {
        self.init(container: ZeptlyDataStore.shared)
    }

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func seedIfNeeded() throws {
        let metadata = try context.fetch(
            FetchDescriptor<StoreMetadataRecord>(
                predicate: #Predicate { $0.key == "sampleSeedVersion" }
            )
        ).first

        guard metadata?.value != seedVersion else {
            return
        }

        let existingChats = try context.fetch(FetchDescriptor<ChatRecord>())
        let existingByID = Dictionary(uniqueKeysWithValues: existingChats.map { ($0.id, $0) })

        for (index, chat) in RezplySampleData.chats.enumerated() {
            if existingByID[chat.id] == nil {
                context.insert(
                    ChatRecord(
                    id: chat.id,
                    name: chat.name,
                    lastActivityLabel: chat.timeLabel,
                    preview: chat.preview,
                    chipTitle: chat.chipTitle,
                    chipSymbol: chat.chipSymbol,
                    avatarSymbol: chat.avatarSymbol,
                    initials: chat.initials,
                    appearanceStyle: index,
                    isUnread: chat.isUnread,
                    isOnline: chat.isOnline
                    )
                )
            }

            if let contactContext = chat.contactContext,
                try self.contactContext(chatID: chat.id) == nil
            {
                context.insert(makeContactRecord(contactContext, chatID: chat.id))
            }

            if try messages(chatID: chat.id).isEmpty {
                let intelligence = RezplySampleData.chatIntelligence(withID: chat.id)
                for (messageIndex, message) in intelligence.messages.enumerated() {
                    context.insert(makeMessageRecord(message, chatID: chat.id, sortIndex: messageIndex))
                }
            }
        }

        if let metadata {
            metadata.value = seedVersion
        } else {
            context.insert(StoreMetadataRecord(key: seedVersionKey, value: seedVersion))
        }

        try context.save()
    }

    func chats() throws -> [ChatRecord] {
        var descriptor = FetchDescriptor<ChatRecord>()
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    func chat(id: String) throws -> ChatRecord? {
        try context.fetch(
            FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.id == id })
        ).first
    }

    func messages(chatID: String) throws -> [ChatMessageRecord] {
        var descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate { $0.chatID == chatID }
        )
        descriptor.sortBy = [SortDescriptor(\.sortIndex)]
        return try context.fetch(descriptor)
    }

    func contactContext(chatID: String) throws -> ContactContextRecord? {
        try context.fetch(
            FetchDescriptor<ContactContextRecord>(predicate: #Predicate { $0.chatID == chatID })
        ).first
    }

    private func makeMessageRecord(_ message: ChatMessage, chatID: String, sortIndex: Int) -> ChatMessageRecord {
        let senderKind: String
        let senderName: String?
        switch message.sender {
        case .user:
            senderKind = "user"
            senderName = nil
        case .contact:
            senderKind = "contact"
            senderName = nil
        case let .other(name):
            senderKind = "other"
            senderName = name
        }

        return ChatMessageRecord(
            id: message.id,
            chatID: chatID,
            senderKind: senderKind,
            senderName: senderName,
            text: message.text,
            normalizedText: MessageTextNormalizer.normalize(message.text),
            timeLabel: message.timeLabel,
            sortIndex: sortIndex
        )
    }

    private func makeContactRecord(_ contact: ContactContext, chatID: String) -> ContactContextRecord {
        let keyFactsData = try? JSONEncoder().encode(contact.keyFacts)
        let keyFactsJSON = keyFactsData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return ContactContextRecord(
            chatID: chatID,
            relationshipSubtitle: contact.relationshipSubtitle,
            relationshipNotes: contact.relationshipNotes,
            keyFactsJSON: keyFactsJSON,
            currentInteractionGoal: contact.currentInteractionGoal,
            preferredPersona: contact.preferredPersona
        )
    }
}
