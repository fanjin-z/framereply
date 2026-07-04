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

    func contactMemories(chatID: String) throws -> [ContactMemoryRecord] {
        var descriptor = FetchDescriptor<ContactMemoryRecord>(
            predicate: #Predicate { $0.chatID == chatID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
        return try context.fetch(descriptor)
    }

    func contactContextValue(chatID: String) throws -> ContactContext {
        let memories = try contactMemories(chatID: chatID).map(\.value)
        return try contactContext(chatID: chatID)?.value(contactMemories: memories)
            ?? ContactContext(
                relationshipSubtitle: "",
                contactMemories: memories,
                currentInteractionGoal: "",
                preferredPersona: "Professional"
            )
    }

    func suggestedReplyCache(chatID: String) throws -> SuggestedReplyCacheRecord? {
        try context.fetch(
            FetchDescriptor<SuggestedReplyCacheRecord>(predicate: #Predicate { $0.chatID == chatID })
        ).first
    }

    func saveSuggestedReplyCache(
        chatID: String,
        historySummary: String,
        summarizedMessageCount: Int,
        summarizedPrefixFingerprint: String,
        replies: [String],
        inputFingerprint: String,
        provider: ProviderPlatform,
        model: ProviderModel,
        promptVersion: Int
    ) throws {
        let repliesData = try JSONEncoder().encode(replies)
        let repliesJSON = String(data: repliesData, encoding: .utf8) ?? "[]"
        let record: SuggestedReplyCacheRecord
        if let existing = try suggestedReplyCache(chatID: chatID) {
            record = existing
        } else {
            record = SuggestedReplyCacheRecord(
                chatID: chatID,
                historySummary: "",
                summarizedMessageCount: 0,
                summarizedPrefixFingerprint: "",
                repliesJSON: "[]",
                inputFingerprint: "",
                provider: provider.rawValue,
                model: model.rawValue,
                promptVersion: promptVersion
            )
            context.insert(record)
        }
        record.historySummary = historySummary
        record.summarizedMessageCount = summarizedMessageCount
        record.summarizedPrefixFingerprint = summarizedPrefixFingerprint
        record.repliesJSON = repliesJSON
        record.inputFingerprint = inputFingerprint
        record.provider = provider.rawValue
        record.model = model.rawValue
        record.promptVersion = promptVersion
        record.generatedAt = Date()
        try context.save()
    }

    func deleteSuggestedReplyCache(chatID: String) throws {
        if let record = try suggestedReplyCache(chatID: chatID) {
            context.delete(record)
            try context.save()
        }
    }

    func deleteChat(id: String) throws {
        guard let chat = try chat(id: id) else {
            return
        }

        let chatID = id
        let messageRecords = try messages(chatID: chatID)
        let contactRecords = try context.fetch(
            FetchDescriptor<ContactContextRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let memoryRecords = try contactMemories(chatID: chatID)
        let importRecords = try imports(chatID: chatID)
        let replyCache = try suggestedReplyCache(chatID: chatID)

        for message in messageRecords {
            context.delete(message)
        }
        for contact in contactRecords {
            context.delete(contact)
        }
        for memory in memoryRecords {
            context.delete(memory)
        }
        for importRecord in importRecords {
            context.delete(importRecord)
        }
        if let replyCache {
            context.delete(replyCache)
        }
        context.delete(chat)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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

    func storedAvatarFingerprints() throws -> [StoredAvatarFingerprint] {
        try chats().compactMap { chat in
            guard let hash = chat.avatarPerceptualHash,
                let featurePrintData = chat.avatarFeaturePrintData,
                let quality = chat.avatarQuality,
                let revision = chat.avatarAlgorithmRevision,
                revision > 0
            else {
                return nil
            }
            return StoredAvatarFingerprint(
                chatID: chat.id,
                perceptualHash: UInt64(bitPattern: hash),
                featurePrintData: featurePrintData,
                quality: quality,
                revision: revision
            )
        }
    }

    func applyImport(
        analysis: ChatImportAnalysis,
        confirmedChatID: String?,
        matchDecision: ChatMatchDecision? = nil,
        avatarArtifact: AvatarArtifact? = nil,
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

        if let avatarArtifact,
            shouldApplyAvatar(
                avatarArtifact,
                to: targetChat,
                matchedExisting: matchedExisting,
                matchDecision: matchDecision
            )
        {
            applyAvatar(avatarArtifact, to: targetChat)
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
        let hasUnknownSenders = mergeResult.messages.contains { $0.senderKind == "unknown" }
        let requiresReview = targetChat.isProvisional || hasUnknownSenders
        let importRecord = ChatImportRecord(
            chatID: targetChat.id,
            transcriptFingerprint: fingerprint,
            provider: provider.rawValue,
            model: model.rawValue,
            confidence: analysis.matchConfidence,
            insertedMessageCount: mergeResult.insertedMessageCount,
            isDuplicate: isDuplicate,
            requiresReview: requiresReview,
            matchDisposition: matchDecision?.disposition.rawValue
                ?? (matchedExisting ? ChatMatchDisposition.confirmed.rawValue : ChatMatchDisposition.review.rawValue),
            suggestedChatID: matchDecision?.suggestedChatID,
            matchReason: matchDecision?.reason.rawValue,
            avatarEvidence: matchDecision?.avatarEvidence.rawValue,
            transcriptEvidence: matchDecision?.transcriptEvidence.rawValue,
            sourceApp: nil
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
            reviewRequired: requiresReview,
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
        try refreshImportReviewState(chatID: chatID)
        try context.save()
    }

    func resolveUnknownSender(
        messageID: UUID,
        as sender: AnalyzedMessageSender,
        participantName: String? = nil
    ) throws {
        guard sender == .user || sender == .contact || sender == .other else {
            return
        }
        guard let message = try context.fetch(
            FetchDescriptor<ChatMessageRecord>(predicate: #Predicate { $0.id == messageID })
        ).first, message.senderKind == "unknown"
        else {
            return
        }

        switch sender {
        case .user:
            message.senderKind = "user"
            message.senderName = nil
        case .contact:
            message.senderKind = "contact"
            message.senderName = nil
        case .other:
            let trimmedName = participantName?.trimmingCharacters(in: .whitespacesAndNewlines)
            message.senderKind = "other"
            message.senderName = trimmedName?.isEmpty == false ? trimmedName : (message.senderName ?? "Participant")
        case .unknown:
            return
        }

        if let chat = try chat(id: message.chatID) {
            chat.updatedAt = Date()
        }
        try refreshImportReviewState(chatID: message.chatID)
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
        for memory in try contactMemories(chatID: provisionalChatID) {
            memory.chatID = targetChatID
        }
        if let replyCache = try suggestedReplyCache(chatID: provisionalChatID) {
            context.delete(replyCache)
        }
        let provisionalImports = try imports(chatID: provisionalChatID)
        for importRecord in provisionalImports {
            importRecord.chatID = targetChatID
            importRecord.transcriptFingerprint = nil
            importRecord.requiresReview = mergeResult.messages.contains { $0.senderKind == "unknown" }
            importRecord.matchDisposition = ChatMatchDisposition.confirmed.rawValue
            importRecord.matchReason = "manual_review_merge"
        }

        if let data = provisionalChat.avatarData,
            let hash = provisionalChat.avatarPerceptualHash,
            let feature = provisionalChat.avatarFeaturePrintData,
            let quality = provisionalChat.avatarQuality,
            let revision = provisionalChat.avatarAlgorithmRevision,
            quality >= 0.08,
            revision == AvatarArtifact.algorithmRevision,
            targetChat.avatarData == nil
                || (provisionalChat.avatarUpdatedAt ?? .distantPast) >= (targetChat.avatarUpdatedAt ?? .distantPast)
        {
            targetChat.avatarData = data
            targetChat.avatarPerceptualHash = hash
            targetChat.avatarFeaturePrintData = feature
            targetChat.avatarQuality = quality
            targetChat.avatarAlgorithmRevision = revision
            targetChat.avatarUpdatedAt = provisionalChat.avatarUpdatedAt
        }
        context.delete(provisionalChat)

        if let latestMessage = mergeResult.messages.last {
            targetChat.preview = latestMessage.text
            targetChat.lastActivityLabel = latestMessage.timeLabel.isEmpty ? "Just now" : latestMessage.timeLabel
        }
        targetChat.updatedAt = Date()
        try refreshImportReviewState(chatID: targetChatID)

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
        case .unknown:
            senderKind = "unknown"
            senderName = nil
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
        return ContactContextRecord(
            chatID: chatID,
            relationshipSubtitle: contact.relationshipSubtitle,
            currentInteractionGoal: contact.currentInteractionGoal,
            preferredPersona: contact.preferredPersona
        )
    }

    private func makeProvisionalChat(from analysis: ChatImportAnalysis) -> ChatRecord {
        let title = analysis.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let participant = analysis.messages.lazy.compactMap { message -> String? in
            guard message.sender == .contact || message.sender == .other else {
                return nil
            }
            let name = message.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name : nil
        }.first
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

    private func applyAvatar(_ artifact: AvatarArtifact, to chat: ChatRecord) {
        chat.avatarData = artifact.imageData
        chat.avatarPerceptualHash = Int64(bitPattern: artifact.perceptualHash)
        chat.avatarFeaturePrintData = artifact.featurePrintData
        chat.avatarQuality = artifact.quality
        chat.avatarAlgorithmRevision = artifact.revision
        chat.avatarUpdatedAt = Date()
    }

    private func shouldApplyAvatar(
        _ artifact: AvatarArtifact,
        to chat: ChatRecord,
        matchedExisting: Bool,
        matchDecision: ChatMatchDecision?
    ) -> Bool {
        guard artifact.quality >= 0.08,
            artifact.revision == AvatarArtifact.algorithmRevision,
            !artifact.imageData.isEmpty,
            !artifact.featurePrintData.isEmpty
        else {
            return false
        }
        guard matchedExisting else { return true }
        guard chat.avatarData != nil,
            let storedHash = chat.avatarPerceptualHash,
            let storedFeature = chat.avatarFeaturePrintData
        else {
            return true
        }
        guard matchDecision?.reason == .confirmedDisplayName else { return false }
        let storedQuality = chat.avatarQuality ?? 0
        if artifact.quality > storedQuality + 0.01 { return true }

        let current = StoredAvatarFingerprint(
            chatID: chat.id,
            perceptualHash: UInt64(bitPattern: storedHash),
            featurePrintData: storedFeature,
            quality: storedQuality,
            revision: chat.avatarAlgorithmRevision ?? 0
        )
        guard let similarity = AvatarIdentityService.similarities(
            artifact: artifact,
            candidates: [current]
        ).first else {
            return false
        }

        // An exact header-name match is trusted enough to accept a clearly changed photo,
        // while retaining a quality floor so a weak crop cannot replace a good avatar.
        return !similarity.passesAbsoluteThresholds
            && artifact.quality >= max(0.08, storedQuality * 0.75)
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

    private func refreshImportReviewState(chatID: String) throws {
        let messageRecords = try messages(chatID: chatID)
        let stillHasUnknownSender = messageRecords.contains { $0.senderKind == "unknown" }
        let isProvisional = try chat(id: chatID)?.isProvisional == true
        let requiresReview = stillHasUnknownSender || isProvisional
        let fingerprint = TranscriptFingerprinter.fingerprint(
            chatID: chatID,
            messages: messageRecords.map(MergeMessage.init(record:))
        )
        for importRecord in try imports(chatID: chatID) where importRecord.requiresReview {
            importRecord.requiresReview = requiresReview
            importRecord.transcriptFingerprint = fingerprint
        }
    }

    private func analyzedSender(for message: ChatMessageRecord) -> AnalyzedMessageSender {
        switch message.senderKind {
        case "user":
            .user
        case "other":
            .other
        case "unknown":
            .unknown
        default:
            .contact
        }
    }
}
