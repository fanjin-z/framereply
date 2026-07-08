//
//  AvatarMark.swift
//  zeptly
//

import SwiftUI
import UIKit

struct AvatarMark: View {
    let initials: String
    let symbolName: String?
    let colors: [Color]
    var imageData: Data? = nil
    var size: CGFloat = 64
    var showsOnline: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.72), lineWidth: 2)
                }
                .shadow(color: RezplyColor.primaryContainer.opacity(0.22), radius: 14, x: 0, y: 8)
                .overlay {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else if let symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: size * 0.36, weight: .medium))
                            .foregroundStyle(RezplyColor.primary)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(
                                color: RezplyColor.deepNavy.opacity(0.32), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(width: size, height: size)

            if showsOnline {
                Circle()
                    .fill(RezplyColor.connected)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: -2, y: -2)
            }
        }
        .frame(width: size, height: size)
    }
}
