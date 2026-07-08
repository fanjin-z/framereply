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
    @State private var context: ContactContext?
    @State private var hasLoaded = false
    @State private var loadError: String?

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
        Group {
            if let context {
                ContactContextView(
                    chat: chat,
                    context: Binding(
                        get: { context },
                        set: { self.context = $0 }
                    )
                )
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Load Contact Context",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onChange(of: context) { _, newValue in
            guard hasLoaded, let newValue else {
                return
            }
            save(newValue)
        }
    }

    private func load() {
        do {
            if let existing = records.first {
                context = existing.value(contactMemories: memoryRecords.map(\.value))
            } else {
                context = .empty(personaID: try PersonaRepository().defaultPersonaID())
                context?.contactMemories = memoryRecords.map(\.value)
            }
            hasLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
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
                personaID: value.personaID,
                personaAssignedAt: value.personaAssignedAt
            )
            modelContext.insert(record)
        }

        record.update(from: value)
        syncMemories(value.contactMemories)
        do {
            try modelContext.save()
        } catch {
            loadError = error.localizedDescription
        }
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
