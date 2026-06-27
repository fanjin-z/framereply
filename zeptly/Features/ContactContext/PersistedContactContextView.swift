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
    @State private var context = ContactContext.empty
    @State private var hasLoaded = false

    init(chat: Chat) {
        self.chat = chat
        let chatID = chat.id
        _records = Query(filter: #Predicate<ContactContextRecord> { $0.chatID == chatID })
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
        context = records.first?.value ?? .empty
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
                relationshipNotes: "",
                keyFactsJSON: "[]",
                currentInteractionGoal: "",
                preferredPersona: "Professional"
            )
            modelContext.insert(record)
        }

        record.update(from: value)
        try? modelContext.save()
    }
}
