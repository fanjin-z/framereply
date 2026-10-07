import PhotosUI
import SwiftUI

struct ChatImportSourceSheet: View {
    @Binding var screenshotSelection: [PhotosPickerItem]
    @Binding var draftingInput: String
    let onPaste: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dictation = GuidanceDictation()
    @FocusState private var isGuidanceFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                EtherealBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Import recent conversation messages.")
                            .font(.subheadline)
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                        draftingInputEditor

                        VStack(spacing: 0) {
                            ImportSourceRow(
                                title: "Chat screenshots",
                                detail: "Select up to 8 images",
                                symbolName: "photo.on.rectangle.angled"
                            ) {
                                PhotosPicker(
                                    selection: $screenshotSelection,
                                    maxSelectionCount: 8,
                                    matching: .images
                                ) {
                                    Label("Choose", systemImage: "photo")
                                }
                                .buttonStyle(.bordered)
                                .buttonSizing(.flexible)
                                .buttonBorderShape(.capsule)
                                .controlSize(.regular)
                                .tint(FrameReplyColor.primary)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Choose Screenshots")
                                .accessibilityHint(
                                    "Opens the photo library to select up to eight chat screenshots."
                                )
                                .accessibilityIdentifier("choose-screenshots")
                            }

                            Divider()
                                .overlay(FrameReplyColor.outlineVariant.opacity(0.42))
                                .padding(.leading, 60)

                            ImportSourceRow(
                                title: "Copied text",
                                detail: "Import text from your clipboard",
                                symbolName: "doc.on.clipboard"
                            ) {
                                PasteButton(payloadType: String.self) { items in
                                    dismiss()
                                    onPaste(items)
                                }
                                .buttonStyle(.bordered)
                                .buttonSizing(.flexible)
                                .buttonBorderShape(.capsule)
                                .controlSize(.regular)
                                .tint(FrameReplyColor.primary)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Paste Copied Text")
                                .accessibilityHint(
                                    "Imports all compatible text items from the clipboard."
                                )
                                .accessibilityIdentifier("paste-copied-messages")
                            }
                        }
                        .glassPanel(cornerRadius: 22)
                        .disabled(
                            dictation.isActive || !DraftingInputLimits.canAccept(draftingInput))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityHint("Closes Add Messages.")
                        .accessibilityIdentifier("close-add-messages")
                }
            }
        }
        .accessibilityIdentifier("add-messages-screen")
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.hidden)
    }

    private var sheetDetents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize {
            return [.large]
        }
        return [.medium]
    }

    private var draftingInputEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reply Guidance")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Spacer(minLength: 12)

                if DraftingInputLimits.shouldShowCounter(for: draftingInput) {
                    Text(
                        "\(draftingInput.count)/\(DraftingInputLimits.maximumCharacterCount)"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .monospacedDigit()
                    .accessibilityLabel(
                        "\(draftingInput.count) of "
                            + "\(DraftingInputLimits.maximumCharacterCount) characters"
                    )
                }
            }

            ReplyGuidanceInput(
                text: $draftingInput,
                isFocused: $isGuidanceFocused,
                dictation: dictation,
                identifier: "import-reply-guidance"
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FrameReplyColor.fieldSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                FrameReplyColor.outlineVariant.opacity(0.48),
                                lineWidth: 1
                            )
                    }
            }

            ReplyGuidanceDictationStatus(
                dictation: dictation, text: draftingInput
            )
        }
        .padding(12)
        .glassPanel(cornerRadius: 22)
    }

}

private struct ImportSourceRow<Action: View>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbolName: String
    private let action: Action
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        symbolName: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.action = action()
    }

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            ZStack {
                Circle()
                    .fill(FrameReplyColor.secondaryContainer.opacity(0.58))

                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 6)
            }

            action
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}
