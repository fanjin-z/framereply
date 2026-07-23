//
//  YourNamesView.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct YourNamesView: View {
    @Query(sort: \SelfAliasRecord.displayLabel)
    private var aliases: [SelfAliasRecord]
    @Query private var chatContexts: [ChatContextRecord]

    @State private var newName = ""
    @State private var aliasBeingRenamed: SelfAliasRecord?
    @State private var renameDraft = ""
    @State private var aliasPendingDeletion: SelfAliasRecord?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    TextField("Name or username", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addName)

                    Button("Add", action: addName)
                        .disabled(IdentityLabelPolicy.displayLabel(newName) == nil)
                }
            } header: {
                Text("Add a name")
            } footer: {
                Text(
                    "Saved names can be suggested when FrameReply needs to identify which sender is you."
                )
            }

            Section {
                if aliases.isEmpty {
                    ContentUnavailableView(
                        "No Saved Names",
                        systemImage: "person.text.rectangle",
                        description: Text("Names you confirm during import will appear here.")
                    )
                } else {
                    ForEach(aliases) { alias in
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
                                Button("Delete", role: .destructive) {
                                    aliasPendingDeletion = alias
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(FrameReplyColor.primary)
                            }
                            .accessibilityLabel("Options for \(alias.displayLabel)")
                        }
                    }
                }
            } header: {
                Text("Your names")
            } footer: {
                Text("Deleting a name doesn’t change existing messages.")
            }
        }
        .navigationTitle("Your Names")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Rename Name",
            isPresented: Binding(
                get: { aliasBeingRenamed != nil },
                set: { if !$0 { aliasBeingRenamed = nil } }
            )
        ) {
            TextField("Name or username", text: $renameDraft)
            Button("Save", action: renameName)
                .disabled(IdentityLabelPolicy.displayLabel(renameDraft) == nil)
            Button("Cancel", role: .cancel) {
                aliasBeingRenamed = nil
            }
        } message: {
            Text("The updated name will apply wherever this identity is remembered.")
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { aliasPendingDeletion != nil },
                set: { if !$0 { aliasPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Name", role: .destructive, action: deleteName)
            Button("Cancel", role: .cancel) {
                aliasPendingDeletion = nil
            }
        } message: {
            Text(
                "Future imports may ask which sender is you again. Existing messages won’t change.")
        }
        .alert("Could Not Update Names", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? String(localized: AppStrings.Common.tryAgain))
        }
    }

    private func usageDescription(for alias: SelfAliasRecord) -> String {
        let count = chatContexts.count { context in
            context.selfAliases.contains { $0 === alias }
        }
        return count == 1 ? "Used in 1 chat" : "Used in \(count) chats"
    }

    private var deleteTitle: String {
        guard let aliasPendingDeletion else { return "Delete name?" }
        return "Delete \(aliasPendingDeletion.displayLabel)?"
    }

    private func addName() {
        do {
            _ = try ChatRepository().addSelfAlias(displayLabel: newName)
            newName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameName() {
        guard let aliasBeingRenamed else { return }
        do {
            try ChatRepository().renameSelfAlias(aliasBeingRenamed, displayLabel: renameDraft)
            self.aliasBeingRenamed = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteName() {
        guard let aliasPendingDeletion else { return }
        do {
            try ChatRepository().deleteSelfAlias(aliasPendingDeletion)
            self.aliasPendingDeletion = nil
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
