import PhotosUI
import SwiftUI

struct ChatImportSourceSheet: View {
    @Binding var screenshotSelection: [PhotosPickerItem]
    let onPaste: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add recent conversation messages from screenshots or copied text.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                PhotosPicker(
                    selection: $screenshotSelection,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    ImportSourceRow(
                        title: "Choose Screenshots",
                        detail: "Select up to eight chat screenshots.",
                        symbolName: "photo.on.rectangle.angled"
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FrameReplyColor.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Paste Copied Messages")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurface)
                            Text("Preserves all text items supplied by the clipboard.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                        }

                        Spacer(minLength: 8)

                        PasteButton(payloadType: String.self) { items in
                            dismiss()
                            onPaste(items)
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 20)
                }

                Text(
                    "Copied text is sent to your selected provider for analysis. FrameReply stores the imported messages in its protected local database, but does not retain a separate copy of the source transcript."
                )
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant)

                Spacer()
            }
            .padding(24)
            .background(EtherealBackground())
            .navigationTitle("Add Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ImportSourceRow: View {
    let title: String
    let detail: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FrameReplyColor.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FrameReplyColor.outline)
        }
        .padding(16)
        .glassPanel(cornerRadius: 20)
    }
}
