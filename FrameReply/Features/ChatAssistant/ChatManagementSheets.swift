//
//  ChatManagementSheets.swift
//  FrameReply
//

import SwiftUI

struct DirectCounterpartSelectionSheet: View {
    let candidateNames: [String]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""

    var body: some View {
        NavigationStack {
            Form {
                if !candidateNames.isEmpty {
                    Section("Detected Names") {
                        ForEach(candidateNames, id: \.self) { name in
                            Button(name) { onSelect(name) }
                        }
                    }
                }

                Section {
                    TextField("Counterpart name", text: $customName)
                        .textInputAutocapitalization(.words)
                    Button("Use Custom Name") {
                        if let name = IdentityLabelPolicy.displayLabel(customName) {
                            onSelect(name)
                        }
                    }
                    .disabled(IdentityLabelPolicy.displayLabel(customName) == nil)
                } header: {
                    Text("Custom Name")
                } footer: {
                    Text(
                        "All non-user messages will be treated as coming from this one person. Original imported sender labels are retained for recovery."
                    )
                }
            }
            .navigationTitle("Choose Counterpart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct EditParticipantNamesSheet: View {
    let chatID: String
    private let repository: ChatRepository

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var aliases: [ChatParticipantAlias]
    @State private var newAlias = ""
    @State private var errorMessage: String?

    init(
        chatID: String,
        displayName: String,
        aliases: [ChatParticipantAlias],
        repository: ChatRepository
    ) {
        self.chatID = chatID
        self.repository = repository
        _displayName = State(initialValue: displayName)
        _aliases = State(initialValue: aliases)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Display name")
                } footer: {
                    Text("This is the name shown throughout FrameReply.")
                }

                Section {
                    ForEach(aliases) { alias in
                        HStack(spacing: 12) {
                            Text(alias.displayLabel)
                                .foregroundStyle(FrameReplyColor.onSurface)

                            Spacer()

                            Menu {
                                Button("Use as Display Name") {
                                    promote(alias)
                                }
                                Button("Remove Name", role: .destructive) {
                                    aliases.removeAll { $0.id == alias.id }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(FrameReplyColor.primary)
                            }
                            .accessibilityLabel("Options for \(alias.displayLabel)")
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Name or username", text: $newAlias)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(addAlias)

                        Button("Add", action: addAlias)
                            .disabled(IdentityLabelPolicy.displayLabel(newAlias) == nil)
                    }
                } header: {
                    Text("Also known as")
                } footer: {
                    Text(
                        "FrameReply uses these names to recognize this person in screenshots and pasted transcripts. Removing one may make a future import require review; existing messages won’t change."
                    )
                }
            }
            .navigationTitle("Edit Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(IdentityLabelPolicy.displayLabel(displayName) == nil)
                }
            }
            .alert("Could Not Update Names", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
            }
        }
    }

    private func addAlias() {
        guard let label = IdentityLabelPolicy.displayLabel(newAlias),
            let key = IdentityLabelPolicy.normalizedKey(label),
            key != IdentityLabelPolicy.normalizedKey(displayName),
            !aliases.contains(where: { $0.normalizedLabel == key })
        else {
            newAlias = ""
            return
        }
        aliases.append(ChatParticipantAlias(displayLabel: label))
        newAlias = ""
    }

    private func promote(_ alias: ChatParticipantAlias) {
        let formerDisplayName = displayName
        displayName = alias.displayLabel
        aliases.removeAll { $0.id == alias.id }
        if let formerLabel = IdentityLabelPolicy.displayLabel(formerDisplayName),
            let formerKey = IdentityLabelPolicy.normalizedKey(formerLabel),
            formerKey != IdentityLabelPolicy.normalizedKey(displayName),
            !aliases.contains(where: { $0.normalizedLabel == formerKey })
        {
            aliases.append(ChatParticipantAlias(displayLabel: formerLabel))
        }
    }

    private func save() {
        do {
            try repository.updateParticipantNames(
                chatID: chatID,
                displayName: displayName,
                aliases: aliases
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
