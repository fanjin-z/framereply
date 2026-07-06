//
//  ChatRepository.swift
//  zeptly
//

import Foundation
import SwiftData

nonisolated enum DraftingInputState: String, Codable, Equatable, Sendable {
    case pending
    case submitted
    case skipped
}

nonisolated enum DraftingInputConsumption: Equatable, Sendable {
    case pending
    case submitted(String)
    case skipped
    case missing
    case operationMismatch
    case expired
    case alreadyConsumed
}

nonisolated enum DraftingInputSynchronizationError: Error, Equatable, Sendable {
    case importUnavailable
}

nonisolated enum DraftingInputBarrier {
    static func waitUntilReady(
        pollInterval: Duration = .milliseconds(150),
        read: @escaping @Sendable () async throws -> DraftingInputConsumption
    ) async throws -> DraftingInputConsumption {
        while true {
            try Task.checkCancellation()
            let result = try await read()
            guard result == .pending else { return result }
            try await Task.sleep(for: pollInterval)
        }
    }
}

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

    init(context: ModelContext) {
        self.context = context
    }

    nonisolated deinit {}

    func seedIfNeeded() throws {
        try purgeExpiredDraftingInputs()
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
                personaID: PersonaDefaults.professionalID,
                personaAssignedAt: Date()
            )
    }

    func suggestedReplyCache(chatID: String) throws -> SuggestedReplyCacheRecord? {
        try context.fetch(
            FetchDescriptor<SuggestedReplyCacheRecord>(predicate: #Predicate { $0.chatID == chatID })
        ).first
    }

    func importRecord(id: UUID) throws -> ChatImportRecord? {
        try context.fetch(
            FetchDescriptor<ChatImportRecord>(predicate: #Predicate { $0.id == id })
        ).first
    }

    @discardableResult
    func resolveDraftingInput(
        _ input: String?,
        importID: UUID,
        operationID: UUID,
        now: Date = Date()
    ) throws -> DraftingInputState {
        guard let record = try importRecord(id: importID), record.operationID == operationID else {
            throw DraftingInputSynchronizationError.importUnavailable
        }
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = trimmed.map { String($0.prefix(2_000)) }
        record.draftingInput = limited?.isEmpty == false ? limited : nil
        let state: DraftingInputState = record.draftingInput == nil ? .skipped : .submitted
        record.draftingInputStateRaw = state.rawValue
        record.draftingInputCreatedAt = state == .submitted ? now : nil
        try context.save()
        return state
    }

    /// Reads the readiness state and atomically clears submitted one-use text.
    /// A fresh repository/context should be used for each call by Shortcut code.
    func consumeDraftingInputIfReady(
        importID: UUID,
        operationID: UUID,
        now: Date = Date(),
        lifetime: TimeInterval = 15 * 60
    ) throws -> DraftingInputConsumption {
        guard let record = try importRecord(id: importID) else { return .missing }
        guard record.operationID == operationID else { return .operationMismatch }
        guard let rawState = record.draftingInputStateRaw,
            let state = DraftingInputState(rawValue: rawState)
        else {
            return .operationMismatch
        }

        switch state {
        case .pending:
            let age = now.timeIntervalSince(record.createdAt)
            return age >= 0 && age <= lifetime ? .pending : .expired
        case .skipped:
            return .skipped
        case .submitted:
            guard let createdAt = record.draftingInputCreatedAt else { return .alreadyConsumed }
            let age = now.timeIntervalSince(createdAt)
            guard age >= 0 && age <= lifetime else {
                record.draftingInput = nil
                record.draftingInputCreatedAt = nil
                try context.save()
                return .expired
            }
            guard let value = record.draftingInput, !value.isEmpty else { return .alreadyConsumed }
            record.draftingInput = nil
            record.draftingInputCreatedAt = nil
            try context.save()
            return .submitted(value)
        }
    }

    func purgeExpiredDraftingInputs(
        now: Date = Date(),
        lifetime: TimeInterval = 15 * 60
    ) throws {
        let records = try context.fetch(FetchDescriptor<ChatImportRecord>())
        var changed = false
        for record in records where record.draftingInput != nil {
            let age = record.draftingInputCreatedAt.map { now.timeIntervalSince($0) }
            guard age.map({ $0 < 0 || $0 > lifetime }) ?? true else { continue }
            record.draftingInput = nil
            record.draftingInputCreatedAt = nil
            changed = true
        }
        if changed {
            try context.save()
        }
    }

    func persona(id: UUID) throws -> PersonaRecord? {
        try context.fetch(FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func personaTraits(personaID: UUID) throws -> [PersonaLearnedTraitRecord] {
        try context.fetch(
            FetchDescriptor<PersonaLearnedTraitRecord>(predicate: #Predicate { $0.personaID == personaID })
        )
    }

    func personaAdjustments(personaID: UUID) throws -> [PersonaStyleAdjustmentRecord] {
        try context.fetch(
            FetchDescriptor<PersonaStyleAdjustmentRecord>(predicate: #Predicate { $0.personaID == personaID })
        )
    }

    func personaPromptContext(personaID: UUID) throws -> PersonaPromptContext {
        let record = try persona(id: personaID)
            ?? persona(id: PersonaDefaults.professionalID)
            ?? PersonaRepository.makeBuiltIn(.professional)
        let traits = try personaTraits(personaID: record.id)
            .filter { $0.status == PersonaTraitStatus.active.rawValue }
        return PersonaRepository.promptContext(
            record: record,
            traits: traits,
            adjustments: try personaAdjustments(personaID: record.id)
        )
    }

    func projectedPersonaPromptContext(
        personaID: UUID,
        changes: [PersonaTraitChange]
    ) throws -> PersonaPromptContext {
        let record = try persona(id: personaID)
            ?? persona(id: PersonaDefaults.professionalID)
            ?? PersonaRepository.makeBuiltIn(.professional)
        var traits = try personaTraits(personaID: record.id).map(\.value)
        for change in changes {
            guard let definition = PersonaStyleDimensionRegistry.definition(for: change.dimensionKey),
                definition.learnable,
                definition.observationOnly == (change.levelBand == nil)
            else { continue }
            if let index = traits.firstIndex(where: { $0.dimensionKey == change.dimensionKey }) {
                guard traits[index].origin != .userConfirmed, traits[index].status != .dismissed else { continue }
                let previousCount = traits[index].evidenceCount
                let addedCount = change.sourceMessageIDs.count
                if let level = change.levelBand?.level {
                    let previous = traits[index].learnedLevel ?? level
                    traits[index].learnedLevel = (
                        previous * Double(previousCount) + level * Double(addedCount)
                    ) / Double(previousCount + addedCount)
                }
                traits[index].observation = change.observation
                traits[index].evidenceCount += addedCount
                traits[index].confidence = PersonaStyleResolver.confidence(
                    evidenceCount: traits[index].evidenceCount, origin: .aiInferred
                )
            } else {
                let evidenceCount = change.sourceMessageIDs.count
                traits.append(PersonaLearnedTrait(
                    id: UUID(), dimensionKey: change.dimensionKey,
                    learnedLevel: change.levelBand?.level,
                    observation: change.observation,
                    confidence: PersonaStyleResolver.confidence(evidenceCount: evidenceCount, origin: .aiInferred),
                    evidenceCount: evidenceCount, origin: .aiInferred, status: .active,
                    updatedAt: Date()
                ))
            }
        }
        let adjustments = Dictionary(uniqueKeysWithValues: try personaAdjustments(personaID: record.id).map {
            ($0.dimensionKey, $0.adjustment)
        })
        let descriptive = traits.filter { trait in
            guard trait.status == .active else { return false }
            guard let definition = PersonaStyleDimensionRegistry.definition(for: trait.dimensionKey) else { return false }
            return definition.observationOnly || trait.origin == .userConfirmed
        }
        return PersonaPromptContext(
            id: record.id, name: record.name,
            purposeInstructions: record.purposeInstructions,
            resolvedStyle: PersonaStyleResolver.resolve(
                baseline: record.baselineStyle, adjustments: adjustments, traits: traits
            ),
            descriptiveObservations: descriptive,
            alwaysFollowRules: record.alwaysFollowRules,
            registryVersion: PersonaStyleDimensionRegistry.version,
            resolverVersion: PersonaStyleResolver.version
        )
    }

    func personaLearningMessages(
        chatID: String, personaID: UUID, assignedAt: Date, limit: Int = 30
    ) throws -> [ChatMessageRecord] {
        guard let persona = try persona(id: personaID), persona.learningEnabled else { return [] }
        let cutoff = max(assignedAt, persona.learningEnabledAt)
        let receiptIDs = Set(try context.fetch(
            FetchDescriptor<PersonaLearningReceiptRecord>(predicate: #Predicate {
                $0.personaID == personaID && $0.chatID == chatID
            })
        ).map(\.messageID))
        return try messages(chatID: chatID)
            .filter { $0.senderKind == "user" && $0.createdAt >= cutoff && !receiptIDs.contains($0.id) }
            .prefix(limit)
            .map { $0 }
    }

    func saveSuggestedReplyGeneration(
        chatID: String,
        contactMemories: [ContactMemory],
        personaID: UUID,
        personaTraitChanges: [PersonaTraitChange],
        learningMessageIDs: Set<UUID>,
        historySummary: String,
        summarizedMessageCount: Int,
        summarizedPrefixFingerprint: String,
        replies: [String],
        inputFingerprint: String,
        provider: ProviderPlatform,
        model: ProviderModel,
        promptVersion: Int
    ) throws {
        do {
            let storedMemories = try self.contactMemories(chatID: chatID)
            let recordsByID = Dictionary(uniqueKeysWithValues: storedMemories.map { ($0.id, $0) })
            for memory in contactMemories {
                if let record = recordsByID[memory.id] {
                    record.update(from: memory)
                } else {
                    context.insert(ContactMemoryRecord(chatID: chatID, value: memory))
                }
            }

            try reconcilePersonaTraits(
                personaID: personaID,
                changes: personaTraitChanges,
                allowedMessageIDs: learningMessageIDs
            )
            let now = Date()
            for messageID in learningMessageIDs {
                let key = "\(personaID.uuidString.lowercased())|\(messageID.uuidString.lowercased())"
                let exists = try context.fetch(
                    FetchDescriptor<PersonaLearningReceiptRecord>(predicate: #Predicate { $0.key == key })
                ).first != nil
                if !exists {
                    context.insert(PersonaLearningReceiptRecord(personaID: personaID, chatID: chatID, messageID: messageID, analyzedAt: now))
                }
            }
            if !learningMessageIDs.isEmpty, let persona = try persona(id: personaID) {
                persona.sampleCount += learningMessageIDs.count
                persona.lastLearnedAt = now
                persona.updatedAt = now
            }

            let repliesData = try JSONEncoder().encode(replies)
            let repliesJSON = String(data: repliesData, encoding: .utf8) ?? "[]"
            let cache: SuggestedReplyCacheRecord
            if let existing = try suggestedReplyCache(chatID: chatID) {
                cache = existing
            } else {
                cache = SuggestedReplyCacheRecord(
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
                context.insert(cache)
            }
            cache.historySummary = historySummary
            cache.summarizedMessageCount = summarizedMessageCount
            cache.summarizedPrefixFingerprint = summarizedPrefixFingerprint
            cache.repliesJSON = repliesJSON
            cache.inputFingerprint = inputFingerprint
            cache.provider = provider.rawValue
            cache.model = model.rawValue
            cache.promptVersion = promptVersion
            cache.generatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func reconcilePersonaTraits(
        personaID: UUID,
        changes: [PersonaTraitChange],
        allowedMessageIDs: Set<UUID>
    ) throws {
        var storedByDimension = Dictionary(
            uniqueKeysWithValues: try personaTraits(personaID: personaID).map { ($0.dimensionKey, $0) }
        )
        for change in changes {
            guard !change.sourceMessageIDs.isEmpty,
                change.sourceMessageIDs.allSatisfy(allowedMessageIDs.contains),
                let definition = PersonaStyleDimensionRegistry.definition(for: change.dimensionKey),
                definition.learnable,
                definition.observationOnly == (change.levelBand == nil)
            else { continue }
            if let current = storedByDimension[change.dimensionKey] {
                guard current.origin != PersonaTraitOrigin.userConfirmed.rawValue,
                    current.status != PersonaTraitStatus.dismissed.rawValue
                else { continue }
                let previousCount = current.evidenceCount
                let addedCount = change.sourceMessageIDs.count
                if let level = change.levelBand?.level {
                    let previous = current.learnedLevel ?? level
                    current.learnedLevel = (
                        previous * Double(previousCount) + level * Double(addedCount)
                    ) / Double(previousCount + addedCount)
                }
                current.observation = change.observation
                current.evidenceCount += addedCount
                current.confidence = PersonaStyleResolver.confidence(
                    evidenceCount: current.evidenceCount, origin: .aiInferred
                )
                current.updatedAt = Date()
            } else {
                let evidenceCount = change.sourceMessageIDs.count
                let record = PersonaLearnedTraitRecord(
                    personaID: personaID, dimensionKey: change.dimensionKey,
                    learnedLevel: change.levelBand?.level,
                    observation: change.observation,
                    confidence: PersonaStyleResolver.confidence(
                        evidenceCount: evidenceCount, origin: .aiInferred
                    ),
                    evidenceCount: evidenceCount,
                    origin: PersonaTraitOrigin.aiInferred.rawValue
                )
                context.insert(record)
                storedByDimension[change.dimensionKey] = record
            }
        }
    }

    func savePersonaExampleAnalysis(
        personaID: UUID,
        changes: [PersonaTraitChange],
        sampleMessageIDs: Set<UUID>,
        sampleCount: Int
    ) throws {
        do {
            try reconcilePersonaTraits(
                personaID: personaID,
                changes: changes,
                allowedMessageIDs: sampleMessageIDs
            )
            if let persona = try persona(id: personaID) {
                persona.sampleCount += sampleCount
                persona.lastLearnedAt = Date()
                persona.updatedAt = Date()
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
        let learningReceipts = try context.fetch(
            FetchDescriptor<PersonaLearningReceiptRecord>(predicate: #Predicate { $0.chatID == chatID })
        )

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
        for receipt in learningReceipts {
            context.delete(receipt)
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
            sourceApp: nil,
            diagnosticID: traceID.diagnosticID,
            matchedExisting: matchedExisting,
            operationID: traceID.value,
            draftingInputStateRaw: DraftingInputState.pending.rawValue
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
            personaID: contact.personaID,
            personaAssignedAt: contact.personaAssignedAt
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
