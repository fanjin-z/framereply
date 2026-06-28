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

    func matchCandidates(recentMessageLimit: Int = 12) throws -> [ChatMatchCandidate] {
        try chats().map { chat in
            let recentMessages = try messages(chatID: chat.id).suffix(recentMessageLimit).map { message in
                let sender: String
                if message.senderKind == "other" {
                    sender = ChatImportMatcher.senderKey(.other, name: message.senderName)
                } else {
                    sender = message.senderKind
                }
                return ChatCandidateMessage(
                    sender: sender,
                    text: message.text,
                    timeLabel: message.timeLabel
                )
            }
            return ChatMatchCandidate(id: chat.id, name: chat.name, recentMessages: recentMessages)
        }
    }

    func applyImport(
        analysis: ChatImportAnalysis,
        confirmedChatID: String?,
        provider: ProviderPlatform,
        model: ProviderModel,
        traceID: ImportTraceID = ImportTraceID()
    ) throws -> ScreenshotImportOutcome {
        var matchedExisting = false
        let targetChat: ChatRecord

        if let confirmedChatID, let existingChat = try chat(id: confirmedChatID) {
            targetChat = existingChat
            matchedExisting = true
        } else {
            targetChat = makeProvisionalChat(from: analysis)
            context.insert(targetChat)
            context.insert(makeContactRecord(.empty, chatID: targetChat.id))
        }

        let existingRecords = try messages(chatID: targetChat.id)
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let mergeResult = ChatMessageMerger.merge(
            existing: existingRecords.map(MergeMessage.init(record:)),
            imported: analysis.messages.map(MergeMessage.init(analyzed:))
        )

        for (sortIndex, message) in mergeResult.messages.enumerated() {
            if let existingID = message.existingID, let record = existingByID[existingID] {
                record.sortIndex = sortIndex
            } else {
                context.insert(
                    ChatMessageRecord(
                        chatID: targetChat.id,
                        senderKind: persistedSenderKind(message.senderKind),
                        senderName: message.senderName,
                        text: message.text,
                        normalizedText: message.normalizedText,
                        timeLabel: message.timeLabel,
                        timestamp: message.timestamp,
                        sortIndex: sortIndex
                    )
                )
            }
        }

        if let latestMessage = mergeResult.messages.last {
            targetChat.preview = latestMessage.text
            targetChat.lastActivityLabel = latestMessage.timeLabel.isEmpty ? "Just now" : latestMessage.timeLabel
        }
        targetChat.updatedAt = Date()

        let fingerprint = TranscriptFingerprinter.fingerprint(
            chatID: targetChat.id,
            messages: mergeResult.messages
        )
        let targetChatID = targetChat.id
        let transcriptFingerprint = fingerprint
        let previousImport = try context.fetch(
            FetchDescriptor<ChatImportRecord>(
                predicate: #Predicate {
                    $0.chatID == targetChatID && $0.transcriptFingerprint == transcriptFingerprint
                }
            )
        ).first
        let isDuplicate = mergeResult.insertedMessageCount == 0 || previousImport != nil
        let importRecord = ChatImportRecord(
            chatID: targetChat.id,
            transcriptFingerprint: fingerprint,
            provider: provider.rawValue,
            model: model.rawValue,
            confidence: analysis.matchConfidence,
            insertedMessageCount: mergeResult.insertedMessageCount,
            isDuplicate: isDuplicate,
            requiresReview: targetChat.isProvisional
        )
        context.insert(importRecord)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return ScreenshotImportOutcome(
            chatID: targetChat.id,
            chatName: targetChat.name,
            importID: importRecord.id,
            diagnosticID: traceID.diagnosticID,
            matchedExisting: matchedExisting,
            reviewRequired: targetChat.isProvisional,
            duplicate: isDuplicate,
            insertedMessageCount: mergeResult.insertedMessageCount
        )
    }

    func confirmProvisionalChat(chatID: String, name: String) throws {
        guard let chat = try chat(id: chatID), chat.isProvisional else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            chat.name = trimmedName
            chat.initials = initials(for: trimmedName)
        }
        chat.isProvisional = false
        chat.chipTitle = "General"
        chat.chipSymbol = "number"
        chat.updatedAt = Date()
        try markImportsReviewed(chatID: chatID)
        try context.save()
    }

    func mergeProvisionalChat(_ provisionalChatID: String, into targetChatID: String) throws {
        guard provisionalChatID != targetChatID,
            let provisionalChat = try chat(id: provisionalChatID),
            provisionalChat.isProvisional,
            let targetChat = try chat(id: targetChatID)
        else {
            return
        }

        let targetMessages = try messages(chatID: targetChatID)
        let provisionalMessages = try messages(chatID: provisionalChatID)
        let targetByID = Dictionary(uniqueKeysWithValues: targetMessages.map { ($0.id, $0) })
        let imported = provisionalMessages.map { message in
            MergeMessage(
                analyzed: AnalyzedChatMessage(
                    sender: analyzedSender(for: message),
                    senderName: message.senderName,
                    text: message.text,
                    timestampLabel: message.timeLabel
                )
            )
        }
        let mergeResult = ChatMessageMerger.merge(
            existing: targetMessages.map(MergeMessage.init(record:)),
            imported: imported
        )

        for (sortIndex, message) in mergeResult.messages.enumerated() {
            if let existingID = message.existingID, let record = targetByID[existingID] {
                record.sortIndex = sortIndex
            } else {
                context.insert(
                    ChatMessageRecord(
                        chatID: targetChatID,
                        senderKind: persistedSenderKind(message.senderKind),
                        senderName: message.senderName,
                        text: message.text,
                        normalizedText: message.normalizedText,
                        timeLabel: message.timeLabel,
                        timestamp: message.timestamp,
                        sortIndex: sortIndex
                    )
                )
            }
        }

        for message in provisionalMessages {
            context.delete(message)
        }
        if let contact = try contactContext(chatID: provisionalChatID) {
            context.delete(contact)
        }
        let provisionalImports = try imports(chatID: provisionalChatID)
        for importRecord in provisionalImports {
            importRecord.chatID = targetChatID
            importRecord.transcriptFingerprint = nil
            importRecord.requiresReview = false
        }
        context.delete(provisionalChat)

        if let latestMessage = mergeResult.messages.last {
            targetChat.preview = latestMessage.text
            targetChat.lastActivityLabel = latestMessage.timeLabel.isEmpty ? "Just now" : latestMessage.timeLabel
        }
        targetChat.updatedAt = Date()

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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

    private func makeProvisionalChat(from analysis: ChatImportAnalysis) -> ChatRecord {
        let title = analysis.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let participant = analysis.participants.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [title, participant].compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }.first ?? "Imported Chat"
        let chatInitials = initials(for: name)

        return ChatRecord(
            id: UUID().uuidString.lowercased(),
            name: name,
            lastActivityLabel: "Just now",
            preview: analysis.messages.last?.text ?? "Imported conversation",
            chipTitle: "Review Import",
            chipSymbol: "exclamationmark.bubble",
            avatarSymbol: nil,
            initials: chatInitials.isEmpty ? "IC" : chatInitials,
            appearanceStyle: (try? chats().count) ?? 0,
            isUnread: false,
            isOnline: false,
            isProvisional: true
        )
    }

    private func persistedSenderKind(_ comparisonKey: String) -> String {
        comparisonKey.hasPrefix("other:") ? "other" : comparisonKey
    }

    private func initials(for name: String) -> String {
        name
            .split(whereSeparator: \Character.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func imports(chatID: String) throws -> [ChatImportRecord] {
        try context.fetch(
            FetchDescriptor<ChatImportRecord>(predicate: #Predicate { $0.chatID == chatID })
        )
    }

    private func markImportsReviewed(chatID: String) throws {
        for importRecord in try imports(chatID: chatID) {
            importRecord.requiresReview = false
        }
    }

    private func analyzedSender(for message: ChatMessageRecord) -> AnalyzedMessageSender {
        switch message.senderKind {
        case "user":
            .user
        case "other":
            .other
        default:
            .contact
        }
    }
}
