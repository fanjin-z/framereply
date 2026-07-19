//
//  PickerField.swift
//  FrameReply
//

import SwiftUI

struct PickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack {
                    Text(selection)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(FrameReplyColor.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
        }
    }
}
