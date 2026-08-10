//
//  PersonalInfoView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct PersonalInfoView: View {
    private let repository: ChatRepository
    @Query(sort: \SelfAliasRecord.displayLabel)
    private var aliases: [SelfAliasRecord]
    @Query private var chatContexts: [ChatContextRecord]
    @Query(
        filter: #Predicate<PersonalInfoFactRecord> { $0.status == "active" },
        sort: \PersonalInfoFactRecord.text
    )
    private var facts: [PersonalInfoFactRecord]
    @State private var newName = ""
    @State private var aliasBeingRenamed: SelfAliasRecord?
    @State private var renameDraft = ""
    @State private var aliasPendingDeletion: SelfAliasRecord?
    @State private var newFact = ""
    @State private var factBeingEdited: PersonalInfoFactRecord?
    @State private var factEditDraft = ""
    @State private var factPendingDeletion: PersonalInfoFactRecord?
    @State private var learningEnabled = true
    @State private var errorMessage: String?

    init(repository: ChatRepository) {
        self.repository = repository
    }

    var body: some View {
        Form {
            Section {
                aliasComposer

                ForEach(aliases) { alias in
                    aliasRow(alias)
                }
            } header: {
                Text("Your Names in Chats")
            } footer: {
                Text("Helps FrameReply recognize you in chats.")
            }

            Section {
                Toggle("Learn from my messages", isOn: learningEnabledBinding)
                    .accessibilityIdentifier("personal-info-learning-toggle")

                factComposer

                ForEach(facts) { fact in
                    factRow(fact)
                }
            } header: {
                Text("Facts About You")
            } footer: {
                if isAtFactCapacity {
                    Text("You have 50 saved details. Remove one to add another.")
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
            }
        }
        .accessibilityIdentifier("personal-info-screen")
        .navigationTitle("Personal Info")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                learningEnabled = try repository.personalInfoLearningEnabled()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Rename Name",
            isPresented: Binding(
                get: { aliasBeingRenamed != nil },
                set: { if !$0 { aliasBeingRenamed = nil } }
            )
        ) {
            TextField("Name, nickname, or username", text: $renameDraft)
            Button("Save", action: renameName)
                .disabled(IdentityLabelPolicy.displayLabel(renameDraft) == nil)
            Button("Cancel", role: .cancel) { aliasBeingRenamed = nil }
        } message: {
            Text("The updated name will apply wherever this identity is remembered.")
        }
        .alert(
            "Edit Personal Info",
            isPresented: Binding(
                get: { factBeingEdited != nil },
                set: { if !$0 { factBeingEdited = nil } }
            )
        ) {
            TextField("One short fact about yourself", text: $factEditDraft)
            Button("Save", action: saveFactEdit)
                .disabled(!isValidPersonalInfoText(factEditDraft))
            Button("Cancel", role: .cancel) { factBeingEdited = nil }
        } message: {
            Text("Your edit will stay as written.")
        }
        .confirmationDialog(
            deleteNameTitle,
            isPresented: Binding(
                get: { aliasPendingDeletion != nil },
                set: { if !$0 { aliasPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Name", role: .destructive, action: deleteName)
            Button("Cancel", role: .cancel) { aliasPendingDeletion = nil }
        } message: {
            Text(
                "Future imports may ask which sender is you again. Existing messages won’t change."
            )
        }
        .confirmationDialog(
            "Remove this item?",
            isPresented: Binding(
                get: { factPendingDeletion != nil },
                set: { if !$0 { factPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: deleteFact)
            Button("Cancel", role: .cancel) { factPendingDeletion = nil }
        } message: {
            Text("FrameReply won’t add it again.")
        }
        .alert("Could Not Update Personal Info", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private var aliasComposer: some View {
        HStack(spacing: 10) {
            TextField("Name, nickname, or username", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(addName)

            Button("Add", action: addName)
                .disabled(IdentityLabelPolicy.displayLabel(newName) == nil)
        }
    }

    private var factComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Add one short fact about yourself", text: $newFact, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit(addFact)
                    .disabled(isAtFactCapacity)

                Button("Add", action: addFact)
                    .disabled(isAtFactCapacity || !isValidPersonalInfoText(newFact))
                    .accessibilityIdentifier("add-personal-info-fact")
            }
            Text("\(newFact.unicodeScalars.count)/\(PersonalInfoLimits.maximumTextCodePoints)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func aliasRow(_ alias: SelfAliasRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alias.displayLabel)
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text(usageDescription(for: alias))
                    .font(.caption)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            Spacer()
            Menu {
                Button("Rename") {
                    aliasBeingRenamed = alias
                    renameDraft = alias.displayLabel
                }
                Button("Delete", role: .destructive) { aliasPendingDeletion = alias }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(FrameReplyColor.primary)
            }
            .accessibilityLabel("Options for \(alias.displayLabel)")
        }
    }

    private func factRow(_ fact: PersonalInfoFactRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.text)
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    fact.origin == PersonalInfoFactOrigin.ai.rawValue
                        ? "Learned from your messages" : "Added by you"
                )
                .font(.caption)
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Edit") {
                    factBeingEdited = fact
                    factEditDraft = fact.text
                }
                Button("Delete", role: .destructive) { factPendingDeletion = fact }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(FrameReplyColor.primary)
            }
            .accessibilityLabel("Options for personal info: \(fact.text)")
        }
    }

    private var learningEnabledBinding: Binding<Bool> {
        Binding(
            get: { learningEnabled },
            set: { value in
                do {
                    try repository.setPersonalInfoLearningEnabled(value)
                    learningEnabled = value
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private var isAtFactCapacity: Bool {
        facts.count >= PersonalInfoLimits.maximumActiveFacts
    }

    private func isValidPersonalInfoText(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty
            && cleaned.unicodeScalars.count <= PersonalInfoLimits.maximumTextCodePoints
    }

    private func usageDescription(for alias: SelfAliasRecord) -> String {
        let count = chatContexts.count { context in
            context.selfAliases.contains { $0 === alias }
        }
        return count == 1 ? "Used in 1 chat" : "Used in \(count) chats"
    }

    private var deleteNameTitle: String {
        guard let aliasPendingDeletion else { return "Delete name?" }
        return "Delete \(aliasPendingDeletion.displayLabel)?"
    }

    private func addName() {
        do {
            _ = try repository.addSelfAlias(displayLabel: newName)
            newName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameName() {
        guard let aliasBeingRenamed else { return }
        do {
            try repository.renameSelfAlias(aliasBeingRenamed, displayLabel: renameDraft)
            self.aliasBeingRenamed = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteName() {
        guard let aliasPendingDeletion else { return }
        do {
            try repository.deleteSelfAlias(aliasPendingDeletion)
            self.aliasPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addFact() {
        do {
            _ = try repository.addPersonalInfoFact(text: newFact)
            newFact = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveFactEdit() {
        guard let factBeingEdited else { return }
        do {
            try repository.updatePersonalInfoFact(factBeingEdited, text: factEditDraft)
            self.factBeingEdited = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFact() {
        guard let factPendingDeletion else { return }
        do {
            try repository.deletePersonalInfoFact(factPendingDeletion)
            self.factPendingDeletion = nil
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
