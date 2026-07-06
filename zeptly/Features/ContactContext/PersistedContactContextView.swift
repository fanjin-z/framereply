//
//  PersistedContactContextView.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct PersistedContactContextView: View {
    let chat: Chat

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ContactContextRecord]
    @Query private var memoryRecords: [ContactMemoryRecord]
    @State private var context = ContactContext.empty
    @State private var hasLoaded = false

    init(chat: Chat) {
        self.chat = chat
        let chatID = chat.id
        _records = Query(filter: #Predicate<ContactContextRecord> { $0.chatID == chatID })
        _memoryRecords = Query(
            filter: #Predicate<ContactMemoryRecord> { $0.chatID == chatID },
            sort: \ContactMemoryRecord.createdAt
        )
    }

    var body: some View {
        ContactContextView(chat: chat, context: $context)
            .onAppear(perform: load)
            .onChange(of: context) { _, newValue in
                guard hasLoaded else {
                    return
                }
                save(newValue)
            }
    }

    private func load() {
        let defaultID = (try? PersonaRepository().defaultPersonaID()) ?? PersonaDefaults.professionalID
        context =
            records.first?.value(contactMemories: memoryRecords.map(\.value))
            ?? ContactContext(
                relationshipSubtitle: "",
                contactMemories: memoryRecords.map(\.value),
                currentInteractionGoal: "",
                personaID: defaultID,
                personaAssignedAt: Date()
            )
        hasLoaded = true
    }

    private func save(_ value: ContactContext) {
        let record: ContactContextRecord
        if let existing = records.first {
            record = existing
        } else {
            record = ContactContextRecord(
                chatID: chat.id,
                relationshipSubtitle: "",
                currentInteractionGoal: "",
                personaID: (try? PersonaRepository().defaultPersonaID()) ?? PersonaDefaults.professionalID,
                personaAssignedAt: Date()
            )
            modelContext.insert(record)
        }

        record.update(from: value)
        syncMemories(value.contactMemories)
        try? modelContext.save()
    }

    private func syncMemories(_ memories: [ContactMemory]) {
        let chatID = chat.id
        let stored =
            (try? modelContext.fetch(
                FetchDescriptor<ContactMemoryRecord>(
                    predicate: #Predicate { $0.chatID == chatID }
                )
            )) ?? []
        let memoriesByID = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

        for memory in memories {
            if let existing = recordsByID[memory.id] {
                existing.update(from: memory)
            } else {
                modelContext.insert(ContactMemoryRecord(chatID: chat.id, value: memory))
            }
        }
        for record in stored where memoriesByID[record.id] == nil {
            modelContext.delete(record)
        }
    }
}
