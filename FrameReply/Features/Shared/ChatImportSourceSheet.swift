import PhotosUI
import SwiftUI

struct ChatImportSourceSheet: View {
    @Binding var screenshotSelection: [PhotosPickerItem]
    let onPaste: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            EtherealBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

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
                            .controlSize(.large)
                            .tint(FrameReplyColor.primary)
                            .frame(height: 44)
                            .accessibilityLabel("Choose Screenshots")
                            .accessibilityHint(
                                "Opens the photo library to select up to eight chat screenshots."
                            )
                            .accessibilityIdentifier("choose-screenshots")
                        }

                        Divider()
                            .overlay(FrameReplyColor.outlineVariant.opacity(0.42))
                            .padding(.leading, 74)

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
                            .controlSize(.large)
                            .tint(FrameReplyColor.primary)
                            .frame(height: 44)
                            .accessibilityLabel("Paste Copied Text")
                            .accessibilityHint(
                                "Imports all compatible text items from the clipboard."
                            )
                            .accessibilityIdentifier("paste-copied-messages")
                        }
                    }
                    .glassPanel(cornerRadius: 22)
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.visible)
    }

    private var sheetDetents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize {
            return [.medium, .large]
        }
        return [.height(360), .medium]
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Add Messages")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)

                Text("Import recent conversation messages.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FrameReplyColor.primary)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.72))
                    }
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Close")
            .accessibilityHint("Closes Add Messages.")
            .accessibilityIdentifier("close-add-messages")
        }
    }
}

private struct ImportSourceRow<Action: View>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbolName: String
    private let action: Action

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
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(FrameReplyColor.secondaryContainer.opacity(0.58))

                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.primary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            action
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }
}
