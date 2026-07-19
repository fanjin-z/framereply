//
//  ChatRepository.swift
//  FrameReply
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

nonisolated enum ChatParticipantNameError: LocalizedError, Equatable, Sendable {
    case chatUnavailable
    case directChatRequired
    case emptyDisplayName

    var errorDescription: String? {
        switch self {
        case .chatUnavailable:
            "That chat is no longer available."
        case .directChatRequired:
            "Participant names are available for one-to-one chats only."
        case .emptyDisplayName:
            "Enter a display name for this chat."
        }
    }
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
    private let seedVersion = "1"
    private let seedVersionKey = "sampleSeedVersion"

    convenience init() {
        self.init(container: FrameReplyDataStore.shared)
    }

    init(container: ModelContainer) {
        context = container.mainContext
        // Persona availability is a store invariant for reply generation and new chats.
        try? PersonaRepository(container: container).seedPersonasIfNeeded()
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

    func selfAliases(chatID: String) throws -> [ChatSelfAliasRecord] {
        var descriptor = FetchDescriptor<ChatSelfAliasRecord>(
            predicate: #Predicate { $0.chatID == chatID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    @discardableResult
    func recordImportReviewExposure(
        chatID: String,
        now: Date = Date(),
        debounceInterval: TimeInterval = 30 * 60
    ) throws -> Bool {
        guard let chat = try chat(id: chatID) else {
            return false
        }
        let hasUnknownSenders = try hasUnknownSenderMessages(chatID: chatID)
        guard var state = chat.importReviewState,
            chat.requiresImportIdentityReview || hasUnknownSenders
        else {
            return false
        }

        let shouldCountView =
            state.lastViewedAt.map { now.timeIntervalSince($0) >= debounceInterval }
            ?? true
        if shouldCountView {
            state.viewCount += 1
            state.lastViewedAt = now
            chat.importReviewState = state
        }

        let dismissed = try dismissImportReviewIfEligible(
            chat,
            now: now
        )
        try context.save()
        return dismissed
    }

    @discardableResult
    func recordImportReviewMeaningfulAction(
        chatID: String,
        now: Date = Date()
    ) throws -> Bool {
        guard let chat = try chat(id: chatID) else {
            return false
        }
        let hasUnknownSenders = try hasUnknownSenderMessages(chatID: chatID)
        guard var state = chat.importReviewState,
            chat.requiresImportIdentityReview || hasUnknownSenders
        else {
            return false
        }

        state.meaningfulActionCount += 1
        chat.importReviewState = state
        let dismissed = try dismissImportReviewIfEligible(
            chat,
            now: now
        )
        try context.save()
        return dismissed
    }

    func chatContext(chatID: String) throws -> ChatContextRecord? {
        try context.fetch(
            FetchDescriptor<ChatContextRecord>(predicate: #Predicate { $0.chatID == chatID })
        ).first
    }

    @discardableResult
    func ensureChatContext(chatID: String) throws -> ChatContextRecord {
        if let existing = try chatContext(chatID: chatID) {
            return existing
        }
        let record = makeChatContextRecord(try emptyChatContext(), chatID: chatID)
        context.insert(record)
        try context.save()
        return record
    }

    @discardableResult
    func updateInteractionGoal(chatID: String, goal: String) throws -> Bool {
        let value = String(
            goal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        )
        let record = try ensureChatContext(chatID: chatID)
        guard record.currentInteractionGoal != value else { return false }
        record.currentInteractionGoal = value
        try context.save()
        return true
    }

    @discardableResult
    func assignPersona(personaID: UUID, toChatID chatID: String, at date: Date = Date()) throws
        -> Bool
    {
        guard try persona(id: personaID) != nil else {
            throw PersonaRepositoryError.invalidDefaultPersona
        }
        let record = try ensureChatContext(chatID: chatID)
        guard record.personaID != personaID else { return false }
        record.personaID = personaID
        record.personaAssignedAt = date
        try context.save()
        return true
    }

    func chatMemories(chatID: String) throws -> [ChatMemoryRecord] {
        var descriptor = FetchDescriptor<ChatMemoryRecord>(
            predicate: #Predicate { $0.chatID == chatID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
        return try context.fetch(descriptor)
    }

    func chatContextValue(chatID: String) throws -> ChatContext {
        let memories = try chatMemories(chatID: chatID).map(\.value)
        return try chatContext(chatID: chatID)?.value(chatMemories: memories)
            ?? ChatContext(
                chatMemories: memories,
                currentInteractionGoal: "",
                personaID: try defaultPersona().id,
                personaAssignedAt: Date()
            )
    }

    func participantAliases(chatID: String) throws -> [ChatParticipantAlias] {
        try chatContext(chatID: chatID)?.participantAliases ?? []
    }

    func updateParticipantNames(
        chatID: String,
        displayName: String,
        aliases suppliedAliases: [ChatParticipantAlias]
    ) throws {
        guard let chat = try chat(id: chatID) else {
            throw ChatParticipantNameError.chatUnavailable
        }
        guard chat.conversationKind == .direct else {
            throw ChatParticipantNameError.directChatRequired
        }
        guard let cleanedDisplayName = ChatParticipantAlias.displayLabel(displayName) else {
            throw ChatParticipantNameError.emptyDisplayName
        }

        let record = try chatContextForMutation(chatID: chatID)
        var aliases = sanitizedParticipantAliases(
            suppliedAliases,
            excludingDisplayName: cleanedDisplayName
        )
        if ChatParticipantAlias.normalizedKey(chat.name)
            != ChatParticipantAlias.normalizedKey(cleanedDisplayName),
            isRetainableParticipantLabel(chat.name)
        {
            aliases.append(ChatParticipantAlias(displayLabel: chat.name))
            aliases = sanitizedParticipantAliases(
                aliases,
                excludingDisplayName: cleanedDisplayName
            )
        }

        chat.name = cleanedDisplayName
        chat.updatedAt = Date()
        record.participantAliases = aliases

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func suggestedReplyCache(chatID: String) throws -> SuggestedReplyCacheRecord? {
        try context.fetch(
            FetchDescriptor<SuggestedReplyCacheRecord>(
                predicate: #Predicate { $0.chatID == chatID })
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
        guard let state = DraftingInputState(rawValue: record.draftingInputStateRaw)
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
        try context.fetch(FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.id == id }))
            .first
    }

    func personaObservations(personaID: UUID) throws -> [PersonaObservationRecord] {
        try context.fetch(
            FetchDescriptor<PersonaObservationRecord>(
                predicate: #Predicate { $0.personaID == personaID })
        )
    }

    func personaPromptContext(personaID: UUID) throws -> PersonaPromptContext {
        let record = try persona(id: personaID) ?? defaultPersona()
        return PersonaRepository.promptContext(
            record: record, observations: try personaObservations(personaID: record.id))
    }

    func projectedPersonaPromptContext(
        personaID: UUID,
        changes: [PersonaObservationChange]
    ) throws -> PersonaPromptContext {
        let record = try persona(id: personaID) ?? defaultPersona()
        var values = try personaObservations(personaID: record.id).map(\.value)
        let allowed = Set(changes.flatMap(\.sourceMessageIDs))
        for change in changes {
            applyProjected(change, to: &values, allowedMessageIDs: allowed)
        }
        return PersonaPromptContext(
            id: record.id, name: record.name, instructions: record.instructions,
            observations: values.filter { $0.status == .active }.sorted {
                if $0.isUserProtected != $1.isUserProtected { return $0.isUserProtected }
                return $0.createdAt < $1.createdAt
            },
            protectedTombstones: values.filter { $0.status == .archived && $0.isUserProtected }
        )
    }

    func personaLearningMessages(
        chatID: String, personaID: UUID, assignedAt: Date, limit: Int = 30
    ) throws -> [ChatMessageRecord] {
        guard let persona = try persona(id: personaID), persona.learningEnabled else { return [] }
        let cutoff = max(assignedAt, persona.learningEnabledAt)
        let receiptIDs = Set(
            try context.fetch(
                FetchDescriptor<PersonaLearningReceiptRecord>(
                    predicate: #Predicate {
                        $0.personaID == personaID && $0.chatID == chatID
                    })
            ).map(\.messageID))
        return try messages(chatID: chatID)
            .filter {
                $0.senderKind == "user" && $0.createdAt >= cutoff && !receiptIDs.contains($0.id)
            }
            .prefix(limit)
            .map { $0 }
    }

    func saveSuggestedReplyGeneration(
        chatID: String,
        chatMemories: [ChatMemory],
        personaID: UUID,
        personaObservationChanges: [PersonaObservationChange],
        learningMessageIDs: Set<UUID>,
        historySummary: String,
        summarizedMessageCount: Int,
        summarizedPrefixFingerprint: String,
        replies: [String],
        conversationStrategy: String,
        strategyRationale: String,
        inputFingerprint: String,
        promptVersion: Int
    ) throws {
        do {
            let storedMemories = try self.chatMemories(chatID: chatID)
            let recordsByID = Dictionary(uniqueKeysWithValues: storedMemories.map { ($0.id, $0) })
            for memory in chatMemories {
                if let record = recordsByID[memory.id] {
                    record.update(from: memory)
                } else {
                    context.insert(ChatMemoryRecord(chatID: chatID, value: memory))
                }
            }

            try reconcilePersonaObservations(
                personaID: personaID,
                changes: personaObservationChanges,
                allowedMessageIDs: learningMessageIDs
            )
            let now = Date()
            for messageID in learningMessageIDs {
                let key =
                    "\(personaID.uuidString.lowercased())|\(messageID.uuidString.lowercased())"
                let exists =
                    try context.fetch(
                        FetchDescriptor<PersonaLearningReceiptRecord>(
                            predicate: #Predicate { $0.key == key })
                    ).first != nil
                if !exists {
                    context.insert(
                        PersonaLearningReceiptRecord(
                            personaID: personaID, chatID: chatID, messageID: messageID))
                }
            }
            if !learningMessageIDs.isEmpty, let persona = try persona(id: personaID) {
                persona.sampleCount += learningMessageIDs.count
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
                    promptVersion: promptVersion
                )
                context.insert(cache)
            }
            cache.historySummary = historySummary
            cache.summarizedMessageCount = summarizedMessageCount
            cache.summarizedPrefixFingerprint = summarizedPrefixFingerprint
            cache.repliesJSON = repliesJSON
            cache.conversationStrategy = conversationStrategy
            cache.strategyRationale = strategyRationale
            cache.inputFingerprint = inputFingerprint
            cache.promptVersion = promptVersion
            cache.generatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Caches reply text without applying generation output to conversation
    /// summaries, chat memory, or persona learning.
    func saveSuggestedRepliesOnly(
        chatID: String,
        replies: [String],
        conversationStrategy: String,
        strategyRationale: String,
        inputFingerprint: String,
        promptVersion: Int
    ) throws {
        do {
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
                    promptVersion: promptVersion
                )
                context.insert(cache)
            }

            cache.repliesJSON = repliesJSON
            cache.conversationStrategy = conversationStrategy
            cache.strategyRationale = strategyRationale
            cache.inputFingerprint = inputFingerprint
            cache.promptVersion = promptVersion
            cache.generatedAt = Date()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func reconcilePersonaObservations(
        personaID: UUID,
        changes: [PersonaObservationChange],
        allowedMessageIDs: Set<UUID>
    ) throws {
        var records = try personaObservations(personaID: personaID)
        for change in changes {
            guard (2...10).contains(change.sourceMessageIDs.count),
                Set(change.sourceMessageIDs).count == change.sourceMessageIDs.count,
                change.sourceMessageIDs.allSatisfy(allowedMessageIDs.contains)
            else { continue }
            let now = Date()
            switch change.action {
            case .add:
                guard change.targetObservationID == nil,
                    let text = cleanedObservation(change.text),
                    activeCount(records) < PersonaLimits.maximumActiveObservations,
                    !containsEquivalent(text, in: records)
                else { continue }
                let value = PersonaRepository.makeObservation(
                    text: text, origin: .ai, isUserProtected: false,
                    now: now
                )
                let record = PersonaObservationRecord(personaID: personaID, value: value)
                context.insert(record)
                records.append(record)
            case .update:
                guard let targetID = change.targetObservationID,
                    let current = records.first(where: {
                        $0.id == targetID && $0.status == PersonaObservationStatus.active.rawValue
                            && !$0.isUserProtected
                    }),
                    let text = cleanedObservation(change.text),
                    !containsEquivalent(text, in: records, excluding: targetID)
                else { continue }
                let value = PersonaRepository.makeObservation(
                    text: text, origin: .ai, isUserProtected: false,
                    now: now
                )
                let replacement = PersonaObservationRecord(personaID: personaID, value: value)
                current.status = PersonaObservationStatus.superseded.rawValue
                current.updatedAt = now
                context.insert(replacement)
                records.append(replacement)
            case .archive:
                guard let targetID = change.targetObservationID,
                    let current = records.first(where: {
                        $0.id == targetID && $0.status == PersonaObservationStatus.active.rawValue
                            && !$0.isUserProtected
                    })
                else { continue }
                current.status = PersonaObservationStatus.archived.rawValue
                current.updatedAt = now
            }
        }
    }

    func savePersonaExampleAnalysis(
        personaID: UUID,
        changes: [PersonaObservationChange],
        sampleMessageIDs: Set<UUID>,
        sampleCount: Int
    ) throws {
        do {
            try reconcilePersonaObservations(
                personaID: personaID,
                changes: changes,
                allowedMessageIDs: sampleMessageIDs
            )
            if let persona = try persona(id: personaID) {
                persona.sampleCount += sampleCount
                persona.updatedAt = Date()
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func defaultPersona() throws -> PersonaRecord {
        try PersonaRepository(context: context).defaultPersona()
    }

    private func applyProjected(
        _ change: PersonaObservationChange,
        to values: inout [PersonaObservation],
        allowedMessageIDs: Set<UUID>
    ) {
        guard (2...10).contains(change.sourceMessageIDs.count),
            Set(change.sourceMessageIDs).count == change.sourceMessageIDs.count,
            change.sourceMessageIDs.allSatisfy(allowedMessageIDs.contains)
        else { return }
        let now = Date()
        switch change.action {
        case .add:
            guard change.targetObservationID == nil,
                let text = cleanedObservation(change.text),
                values.filter({ $0.status == .active }).count
                    < PersonaLimits.maximumActiveObservations,
                !values.contains(where: { normalized($0.text) == normalized(text) })
            else { return }
            values.append(
                PersonaRepository.makeObservation(
                    text: text, origin: .ai, isUserProtected: false,
                    now: now
                ))
        case .update:
            guard let target = change.targetObservationID,
                let index = values.firstIndex(where: {
                    $0.id == target && $0.status == .active && !$0.isUserProtected
                }
                ),
                let text = cleanedObservation(change.text),
                !values.contains(where: {
                    $0.id != target && normalized($0.text) == normalized(text)
                })
            else { return }
            let replacement = PersonaRepository.makeObservation(
                text: text, origin: .ai, isUserProtected: false,
                now: now
            )
            values[index].status = .superseded
            values[index].updatedAt = now
            values.append(replacement)
        case .archive:
            guard let target = change.targetObservationID,
                let index = values.firstIndex(where: {
                    $0.id == target && $0.status == .active && !$0.isUserProtected
                })
            else { return }
            values[index].status = .archived
            values[index].updatedAt = now
        }
    }

    private func activeCount(_ records: [PersonaObservationRecord]) -> Int {
        records.filter { $0.status == PersonaObservationStatus.active.rawValue }.count
    }

    private func containsEquivalent(
        _ text: String,
        in records: [PersonaObservationRecord],
        excluding id: UUID? = nil
    ) -> Bool {
        records.contains {
            $0.id != id && normalized($0.text) == normalized(text)
                && ($0.status == PersonaObservationStatus.active.rawValue || $0.isUserProtected)
        }
    }

    private func cleanedObservation(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.count > 240 ? nil : value
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func renameChat(id: String, name: String) throws {
        guard let chat = try chat(id: id) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        if chat.conversationKind == .direct {
            try updateParticipantNames(
                chatID: id,
                displayName: trimmedName,
                aliases: try participantAliases(chatID: id)
            )
            return
        }

        chat.name = trimmedName
        chat.updatedAt = Date()

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteChat(id: String) throws {
        guard let chat = try chat(id: id) else {
            return
        }

        let chatID = id
        let messageRecords = try messages(chatID: chatID)
        let chatContextRecords = try context.fetch(
            FetchDescriptor<ChatContextRecord>(
                predicate: #Predicate { $0.chatID == chatID }
            )
        )
        let memoryRecords = try chatMemories(chatID: chatID)
        let importRecords = try imports(chatID: chatID)
        let aliasRecords = try selfAliases(chatID: chatID)
        let replyCache = try suggestedReplyCache(chatID: chatID)
        let learningReceipts = try context.fetch(
            FetchDescriptor<PersonaLearningReceiptRecord>(
                predicate: #Predicate { $0.chatID == chatID })
        )

        for message in messageRecords {
            context.delete(message)
        }
        for chatContext in chatContextRecords {
            context.delete(chatContext)
        }
        for memory in memoryRecords {
            context.delete(memory)
        }
        for importRecord in importRecords {
            context.delete(importRecord)
        }
        for aliasRecord in aliasRecords {
            context.delete(aliasRecord)
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
            let recentMessages = try messages(chatID: chat.id).suffix(recentMessageLimit).map {
                message in
                let sender: String
                if message.senderKind == "group_participant" {
                    sender = ChatImportMatcher.senderKey(
                        .groupParticipant,
                        name: message.senderName
                    )
                } else {
                    sender = message.senderKind
                }
                return ChatCandidateMessage(
                    sender: sender,
                    text: message.text,
                    timeLabel: message.timeLabel
                )
            }
            return ChatMatchCandidate(
                id: chat.id,
                name: chat.name,
                participantAliases: try participantAliases(chatID: chat.id).map(\.displayLabel),
                recentMessages: recentMessages
            )
        }
    }

    func applyImport(
        analysis: ChatImportAnalysis,
        confirmedChatID: String?,
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
            context.insert(makeChatContextRecord(try emptyChatContext(), chatID: targetChat.id))
        }

        targetChat.conversationKind = reconciledConversationKind(
            current: targetChat.conversationKind,
            incoming: analysis.conversationKind
        )

        let importedMessages = try applyingStoredIdentity(
            to: analysis.messages,
            chat: targetChat
        )
        let existingRecords = try messages(chatID: targetChat.id)
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let mergeResult = ChatMessageMerger.merge(
            existing: existingRecords.map(MergeMessage.init(record:)),
            imported: importedMessages.map(MergeMessage.init(analyzed:))
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
                        timeLabel: message.timeLabel,
                        sortIndex: sortIndex
                    )
                )
            }
        }

        if let latestMessage = mergeResult.messages.last {
            targetChat.preview = latestMessage.text
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
        let requiresReview = targetChat.requiresImportIdentityReview || hasUnknownSenders
        let importRecord = ChatImportRecord(
            chatID: targetChat.id,
            transcriptFingerprint: fingerprint,
            insertedMessageCount: mergeResult.insertedMessageCount,
            isDuplicate: isDuplicate,
            requiresReview: requiresReview,
            diagnosticID: traceID.diagnosticID,
            matchedExisting: matchedExisting,
            operationID: traceID.value,
            draftingInputStateRaw: DraftingInputState.pending.rawValue
        )
        context.insert(importRecord)

        if matchedExisting,
            let observedLabel = observedDirectParticipantLabel(
                analysis: analysis,
                conversationKind: targetChat.conversationKind
            )
        {
            let identityContext = try chatContextForMutation(chatID: targetChat.id)
            appendParticipantAlias(
                observedLabel,
                to: identityContext,
                displayName: targetChat.name
            )
        }

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
        guard let chat = try chat(id: chatID), chat.requiresImportIdentityReview else {
            return
        }
        if let cleanedName = ChatParticipantAlias.displayLabel(name) {
            if chat.conversationKind == .direct,
                ChatParticipantAlias.normalizedKey(chat.name)
                    != ChatParticipantAlias.normalizedKey(cleanedName)
            {
                let identityContext = try chatContextForMutation(chatID: chatID)
                appendParticipantAlias(
                    chat.name,
                    to: identityContext,
                    displayName: cleanedName
                )
            }
            chat.name = cleanedName
        }
        var state = chat.importReviewState ?? ChatImportReviewState(identityStatus: .needsReview)
        state.identityStatus = .confirmed
        chat.importReviewState = state
        chat.updatedAt = Date()
        try refreshImportReviewState(chatID: chatID)
        try context.save()
    }

    func resolveUnknownSender(
        messageID: UUID,
        as sender: AnalyzedMessageSender,
        participantName: String? = nil
    ) throws {
        guard sender == .user || sender == .otherParticipant || sender == .groupParticipant else {
            return
        }
        guard
            let message = try context.fetch(
                FetchDescriptor<ChatMessageRecord>(predicate: #Predicate { $0.id == messageID })
            ).first, message.senderKind == "unknown"
        else {
            return
        }
        let observedParticipantLabel = message.senderName

        switch sender {
        case .user:
            message.senderKind = "user"
            message.senderName = nil
        case .otherParticipant:
            message.senderKind = "other_participant"
            message.senderName = nil
        case .groupParticipant:
            let trimmedName = participantName?.trimmingCharacters(in: .whitespacesAndNewlines)
            message.senderKind = "group_participant"
            message.senderName =
                trimmedName?.isEmpty == false ? trimmedName : (message.senderName ?? "Participant")
        case .unknown:
            return
        }

        if let chat = try chat(id: message.chatID) {
            if sender == .otherParticipant,
                chat.conversationKind == .direct,
                let observedParticipantLabel
            {
                let identityContext = try chatContextForMutation(chatID: chat.id)
                appendParticipantAlias(
                    observedParticipantLabel,
                    to: identityContext,
                    displayName: chat.name
                )
            }
            chat.updatedAt = Date()
            if var state = chat.importReviewState {
                state.meaningfulActionCount += 1
                chat.importReviewState = state
                _ = try dismissImportReviewIfEligible(chat, now: chat.updatedAt)
            }
        }
        try refreshImportReviewState(chatID: message.chatID)
        try context.save()
    }

    @discardableResult
    func resolveUnknownSenderLabels(
        chatID: String,
        selfLabel: String
    ) throws -> SenderLabelResolutionOutcome {
        guard let chat = try chat(id: chatID),
            let selectedKey = ParticipantLabelNormalizer.key(selfLabel)
        else {
            throw SenderLabelResolutionError.labelUnavailable
        }

        let unknownMessages = try messages(chatID: chatID).filter { $0.senderKind == "unknown" }
        let groups = UnknownSenderLabelGroup.make(from: unknownMessages)
        guard groups.contains(where: { $0.normalizedLabel == selectedKey }) else {
            throw SenderLabelResolutionError.labelUnavailable
        }

        let effectiveKind = effectiveConversationKind(
            stored: chat.conversationKind,
            namedLabelCount: groups.count
        )
        let usesGroupParticipants = effectiveKind == .group || groups.count > 2
        var resolvedUserCount = 0
        var resolvedOtherCount = 0

        for message in unknownMessages {
            guard let labelKey = ParticipantLabelNormalizer.key(message.senderName) else {
                continue
            }
            if labelKey == selectedKey {
                message.senderKind = "user"
                message.senderName = nil
                resolvedUserCount += 1
            } else if usesGroupParticipants {
                message.senderKind = "group_participant"
                message.senderName = ParticipantLabelNormalizer.displayLabel(message.senderName)
                resolvedOtherCount += 1
            } else {
                message.senderKind = "other_participant"
                message.senderName = ParticipantLabelNormalizer.displayLabel(message.senderName)
                resolvedOtherCount += 1
            }
        }

        let selectedDisplayLabel =
            groups.first(where: {
                $0.normalizedLabel == selectedKey
            })?.displayLabel ?? selfLabel
        let resolvedOtherLabel =
            effectiveKind == .direct
            ? groups.first(where: { $0.normalizedLabel != selectedKey })?.displayLabel
            : nil
        var renamedChat = false
        do {
            try insertSelfAliasIfNeeded(
                chatID: chatID,
                normalizedLabel: selectedKey,
                displayLabel: selectedDisplayLabel
            )

            chat.conversationKind = effectiveKind
            if effectiveKind == .direct,
                groups.count == 2,
                chat.requiresImportIdentityReview,
                chat.name == "Imported Chat",
                let otherLabel = resolvedOtherLabel
            {
                chat.name = otherLabel
                renamedChat = true
            }

            if let resolvedOtherLabel {
                let identityContext = try chatContextForMutation(chatID: chatID)
                appendParticipantAlias(
                    resolvedOtherLabel,
                    to: identityContext,
                    displayName: chat.name
                )
            }

            chat.updatedAt = Date()
            if var state = chat.importReviewState {
                state.meaningfulActionCount += 1
                chat.importReviewState = state
            }
            try refreshImportReviewState(chatID: chatID)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        let remainingUnknownCount = try messages(chatID: chatID).filter {
            $0.senderKind == "unknown"
        }.count
        return SenderLabelResolutionOutcome(
            resolvedUserCount: resolvedUserCount,
            resolvedOtherCount: resolvedOtherCount,
            remainingUnknownCount: remainingUnknownCount,
            renamedChat: renamedChat
        )
    }

    func forgetImportedSelfLabels(chatID: String) throws {
        for alias in try selfAliases(chatID: chatID) {
            context.delete(alias)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func mergeProvisionalChat(_ provisionalChatID: String, into targetChatID: String) throws {
        guard provisionalChatID != targetChatID,
            let provisionalChat = try chat(id: provisionalChatID),
            provisionalChat.requiresImportIdentityReview,
            let targetChat = try chat(id: targetChatID)
        else {
            return
        }

        targetChat.conversationKind = reconciledConversationKind(
            current: targetChat.conversationKind,
            incoming: provisionalChat.conversationKind
        )
        let targetAliases = try selfAliases(chatID: targetChatID)
        let provisionalAliases = try selfAliases(chatID: provisionalChatID)
        let combinedAliases = targetAliases + provisionalAliases
        let targetMessages = try messages(chatID: targetChatID)
        let provisionalMessages = try messages(chatID: provisionalChatID)
        let targetIdentityContext = try chatContextForMutation(chatID: targetChatID)
        let provisionalIdentityContext = try chatContext(chatID: provisionalChatID)
        let targetByID = Dictionary(uniqueKeysWithValues: targetMessages.map { ($0.id, $0) })
        let provisionalAnalyzedMessages = provisionalMessages.map { message in
            AnalyzedChatMessage(
                sender: analyzedSender(for: message),
                senderName: message.senderName,
                text: message.text,
                timestampLabel: message.timeLabel
            )
        }
        let imported = applyingIdentity(
            to: provisionalAnalyzedMessages,
            aliasKeys: Set(combinedAliases.map(\.normalizedLabel)),
            conversationKind: targetChat.conversationKind
        ).map { message in
            MergeMessage(
                analyzed: message
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
                        timeLabel: message.timeLabel,
                        sortIndex: sortIndex
                    )
                )
            }
        }

        for message in provisionalMessages {
            context.delete(message)
        }
        if targetChat.conversationKind == .direct {
            let transferredAliases = provisionalIdentityContext?.participantAliases ?? []
            let observedMessageLabel = provisionalMessages.first(where: {
                $0.senderKind == "other_participant"
                    && ChatParticipantAlias.displayLabel($0.senderName) != nil
            })?.senderName
            var participantAliases =
                targetIdentityContext.participantAliases + transferredAliases
            if isRetainableParticipantLabel(provisionalChat.name) {
                participantAliases.append(
                    ChatParticipantAlias(displayLabel: provisionalChat.name)
                )
            }
            if let observedMessageLabel,
                let displayLabel = ChatParticipantAlias.displayLabel(observedMessageLabel)
            {
                participantAliases.append(
                    ChatParticipantAlias(displayLabel: displayLabel)
                )
            }
            targetIdentityContext.participantAliases = sanitizedParticipantAliases(
                participantAliases,
                excludingDisplayName: targetChat.name
            )
        }
        if let provisionalIdentityContext {
            context.delete(provisionalIdentityContext)
        }
        for memory in try chatMemories(chatID: provisionalChatID) {
            memory.chatID = targetChatID
        }
        if let replyCache = try suggestedReplyCache(chatID: provisionalChatID) {
            context.delete(replyCache)
        }
        let provisionalImports = try imports(chatID: provisionalChatID)
        for importRecord in provisionalImports {
            importRecord.chatID = targetChatID
            importRecord.transcriptFingerprint = nil
            importRecord.requiresReview = mergeResult.messages.contains {
                $0.senderKind == "unknown"
            }
        }

        var existingAliasKeys = Set(targetAliases.map(\.normalizedLabel))
        for alias in provisionalAliases {
            if existingAliasKeys.insert(alias.normalizedLabel).inserted {
                alias.chatID = targetChatID
            } else {
                context.delete(alias)
            }
        }

        context.delete(provisionalChat)

        if let latestMessage = mergeResult.messages.last {
            targetChat.preview = latestMessage.text
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

    private func makeChatContextRecord(_ chatContext: ChatContext, chatID: String)
        -> ChatContextRecord
    {
        let record = ChatContextRecord(
            chatID: chatID,
            currentInteractionGoal: chatContext.currentInteractionGoal,
            personaID: chatContext.personaID,
            personaAssignedAt: chatContext.personaAssignedAt
        )
        record.participantAliases = chatContext.participantAliases
        return record
    }

    private func emptyChatContext() throws -> ChatContext {
        ChatContext(
            chatMemories: [], currentInteractionGoal: "",
            personaID: try defaultPersona().id,
            personaAssignedAt: Date()
        )
    }

    private func makeProvisionalChat(from analysis: ChatImportAnalysis) -> ChatRecord {
        let title = analysis.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let participant = analysis.messages.lazy.compactMap { message -> String? in
            guard message.sender == .otherParticipant || message.sender == .groupParticipant else {
                return nil
            }
            let name = message.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name : nil
        }.first
        let name =
            [title, participant].compactMap { value -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }.first ?? "Imported Chat"
        return ChatRecord(
            id: UUID().uuidString.lowercased(),
            name: name,
            preview: analysis.messages.last?.text ?? "Imported conversation",
            conversationKind: analysis.conversationKind,
            isProvisional: true
        )
    }

    private func persistedSenderKind(_ comparisonKey: String) -> String {
        comparisonKey.hasPrefix("group_participant:") ? "group_participant" : comparisonKey
    }

    private func sanitizedParticipantAliases(
        _ aliases: [ChatParticipantAlias],
        excludingDisplayName displayName: String
    ) -> [ChatParticipantAlias] {
        let displayKey = ChatParticipantAlias.normalizedKey(displayName)
        var seen = Set<String>()
        return aliases.compactMap { alias in
            guard let displayLabel = ChatParticipantAlias.displayLabel(alias.displayLabel),
                isRetainableParticipantLabel(displayLabel),
                let key = ChatParticipantAlias.normalizedKey(displayLabel),
                key != displayKey,
                seen.insert(key).inserted
            else {
                return nil
            }
            var value = alias
            value.displayLabel = displayLabel
            return value
        }
    }

    private func isRetainableParticipantLabel(_ value: String?) -> Bool {
        guard let key = ChatParticipantAlias.normalizedKey(value) else { return false }
        return key != ChatParticipantAlias.normalizedKey("Imported Chat")
    }

    private func chatContextForMutation(chatID: String) throws -> ChatContextRecord {
        if let record = try chatContext(chatID: chatID) {
            return record
        }
        let record = makeChatContextRecord(try emptyChatContext(), chatID: chatID)
        context.insert(record)
        return record
    }

    private func appendParticipantAlias(
        _ label: String,
        to record: ChatContextRecord,
        displayName: String
    ) {
        guard let displayLabel = ChatParticipantAlias.displayLabel(label),
            isRetainableParticipantLabel(displayLabel)
        else {
            return
        }
        record.participantAliases = sanitizedParticipantAliases(
            record.participantAliases + [
                ChatParticipantAlias(displayLabel: displayLabel)
            ],
            excludingDisplayName: displayName
        )
    }

    private func observedDirectParticipantLabel(
        analysis: ChatImportAnalysis,
        conversationKind: ChatConversationKind
    ) -> String? {
        guard conversationKind == .direct else { return nil }
        if analysis.titleSource != .unavailable,
            let title = ChatParticipantAlias.displayLabel(analysis.conversationTitle),
            isRetainableParticipantLabel(title)
        {
            return title
        }
        return analysis.messages.lazy.compactMap { message -> String? in
            guard message.sender == .otherParticipant,
                let label = ChatParticipantAlias.displayLabel(message.senderName),
                self.isRetainableParticipantLabel(label)
            else {
                return nil
            }
            return label
        }.first
    }

    private func reconciledConversationKind(
        current: ChatConversationKind,
        incoming: ChatConversationKind
    ) -> ChatConversationKind {
        if current == .group || incoming == .group {
            return .group
        }
        if current == .direct || incoming == .direct {
            return .direct
        }
        return .unknown
    }

    private func effectiveConversationKind(
        stored: ChatConversationKind,
        namedLabelCount: Int
    ) -> ChatConversationKind {
        if stored == .group || namedLabelCount > 2 {
            return .group
        }
        if stored == .direct || namedLabelCount == 2 {
            return .direct
        }
        return .unknown
    }

    private func applyingStoredIdentity(
        to messages: [AnalyzedChatMessage],
        chat: ChatRecord
    ) throws -> [AnalyzedChatMessage] {
        let aliasKeys = Set(try selfAliases(chatID: chat.id).map(\.normalizedLabel))
        return applyingIdentity(
            to: messages,
            aliasKeys: aliasKeys,
            conversationKind: chat.conversationKind
        )
    }

    private func applyingIdentity(
        to messages: [AnalyzedChatMessage],
        aliasKeys: Set<String>,
        conversationKind: ChatConversationKind
    ) -> [AnalyzedChatMessage] {
        guard !aliasKeys.isEmpty else { return messages }

        let namedLabels = Set(
            messages.compactMap {
                ParticipantLabelNormalizer.key($0.senderName ?? $0.outerAuthorLabel)
            })
        let hasMatchingSelfLabel = !namedLabels.isDisjoint(with: aliasKeys)
        guard hasMatchingSelfLabel else { return messages }

        let effectiveKind = effectiveConversationKind(
            stored: conversationKind,
            namedLabelCount: namedLabels.count
        )
        return messages.map { message in
            guard message.sender == .unknown,
                let displayLabel = ParticipantLabelNormalizer.displayLabel(
                    message.senderName ?? message.outerAuthorLabel
                ),
                let labelKey = ParticipantLabelNormalizer.key(displayLabel)
            else {
                return message
            }

            let resolvedSender: AnalyzedMessageSender
            if aliasKeys.contains(labelKey) {
                resolvedSender = .user
            } else if effectiveKind == .group || namedLabels.count > 2 {
                resolvedSender = .groupParticipant
            } else {
                resolvedSender = .otherParticipant
            }

            return AnalyzedChatMessage(
                sender: resolvedSender,
                senderName: resolvedSender == .user ? nil : displayLabel,
                text: message.text,
                timestampLabel: message.timestampLabel,
                outerAlignment: message.outerAlignment,
                outerAuthorLabel: message.outerAuthorLabel,
                senderConfidence: message.senderConfidence,
                senderEvidence: message.senderEvidence
            )
        }
    }

    private func insertSelfAliasIfNeeded(
        chatID: String,
        normalizedLabel: String,
        displayLabel: String
    ) throws {
        guard
            try !selfAliases(chatID: chatID).contains(where: {
                $0.normalizedLabel == normalizedLabel
            })
        else {
            return
        }
        context.insert(
            ChatSelfAliasRecord(
                chatID: chatID,
                displayLabel: displayLabel
            )
        )
    }

    private func imports(chatID: String) throws -> [ChatImportRecord] {
        try context.fetch(
            FetchDescriptor<ChatImportRecord>(predicate: #Predicate { $0.chatID == chatID })
        )
    }

    private func hasUnknownSenderMessages(chatID: String) throws -> Bool {
        try messages(chatID: chatID).contains { $0.senderKind == "unknown" }
    }

    private func dismissImportReviewIfEligible(
        _ chat: ChatRecord,
        now: Date
    ) throws -> Bool {
        guard var state = chat.importReviewState,
            state.identityStatus == .needsReview
        else {
            return false
        }
        guard try !hasUnknownSenderMessages(chatID: chat.id) else {
            return false
        }
        guard state.viewCount >= 1,
            state.meaningfulActionCount >= 2
        else {
            return false
        }

        state.identityStatus = .dismissed
        chat.importReviewState = state
        chat.updatedAt = now
        try refreshImportReviewState(chatID: chat.id)
        return true
    }

    private func refreshImportReviewState(chatID: String) throws {
        let messageRecords = try messages(chatID: chatID)
        let stillHasUnknownSender = messageRecords.contains { $0.senderKind == "unknown" }
        let requiresImportIdentityReview =
            try chat(id: chatID)?.requiresImportIdentityReview == true
        let requiresReview = stillHasUnknownSender || requiresImportIdentityReview
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
        case "group_participant":
            .groupParticipant
        case "unknown":
            .unknown
        default:
            .otherParticipant
        }
    }
}
