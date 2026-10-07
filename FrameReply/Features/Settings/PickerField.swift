//
//  PickerField.swift
//  FrameReply
//

import SwiftUI

struct PickerField: View {
    let title: LocalizedStringResource
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(FrameReplyColor.onSurface)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack {
                    Text(verbatim: selection)
                        .font(.system(.body, design: .rounded, weight: .regular))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FrameReplyColor.fieldSurface)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
