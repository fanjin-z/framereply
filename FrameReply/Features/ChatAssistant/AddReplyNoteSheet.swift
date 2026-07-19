//
//  AddReplyNoteSheet.swift
//  FrameReply
//

import SwiftUI

struct AddReplyNoteSheet: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EtherealBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add Reply Note")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurface)

                        Text("Used once for the next set of replies")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                    }

                    Spacer()

                    Button {
                        KeyboardDismissal.dismiss()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(FrameReplyColor.primary)
                            }
                    }
                    .buttonStyle(SoftPressButtonStyle())
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $note)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 180)

                    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(
                            "Add what happened offline, what you want to accomplish, or anything the screenshot might miss..."
                        )
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.outline)
                        .lineSpacing(4)
                        .padding(20)
                        .allowsHitTesting(false)
                    }
                }
                .glassPanel(cornerRadius: 24)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
