//
//  ChatCaptureControls.swift
//  zeptly
//

import PhotosUI
import SwiftUI

struct ChatCaptureControls: View {
    @Binding var screenshotSelection: [PhotosPickerItem]
    let isImporting: Bool
    let hasContextNote: Bool
    let onContextTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(
                selection: $screenshotSelection,
                maxSelectionCount: 8,
                matching: .images
            ) {
                HStack(spacing: 9) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isImporting ? "Importing…" : "Import Screenshots")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(RezplyColor.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.secondaryContainer.opacity(0.42))
                }
            }
            .buttonStyle(SoftPressButtonStyle())
            .disabled(isImporting)

            Button {
                onContextTap()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: hasContextNote ? "checkmark.bubble" : "text.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(hasContextNote ? "Context Added" : "Add Context")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule(style: .continuous)
                        .fill(RezplyColor.primary)
                        .shadow(
                            color: RezplyColor.primaryContainer.opacity(0.28), radius: 18, x: 0,
                            y: 10)
                }
            }
            .buttonStyle(SoftPressButtonStyle())
        }
    }
}
