//
//  ChatCard.swift
//  FrameReply
//

import Foundation
import SwiftUI

struct ChatCard: View {
    let chat: Chat
    let persona: Persona
    let onChatTap: () -> Void
    let onDeleteTap: () -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 50

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onChatTap) {
                HStack(spacing: 14) {
                    avatar
                    details
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Chat Assistant for \(chat.name)")
            .accessibilityValue(accessibilityValue)

            Menu {
                Button(
                    "Delete Chat",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDeleteTap
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(FrameReplyColor.outline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chat actions for \(chat.name)")
        }
        .padding(.vertical, 12)
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(minHeight: 108)
        .glassPanel(cornerRadius: 22)
    }

    private var avatar: some View {
        AvatarMark(
            initials: chat.initials,
            symbolName: chat.avatarSymbol,
            colors: chat.gradient,
            size: avatarSize
        )
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chat.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Text(ChatActivityDateFormatter.text(for: chat.updatedAt))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(FrameReplyColor.outline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            contextBadge

            Text(chat.preview)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contextBadge: some View {
        switch ChatsPresentation.badge(for: chat, persona: persona) {
        case .reviewImport:
            PillChip(
                title: "Review Import",
                symbolName: "exclamationmark.bubble",
                tint: FrameReplyColor.primary
            )
            .fixedSize(horizontal: true, vertical: false)
        case .persona(let persona):
            ChatPersonaBadge(persona: persona)
        }
    }

    private var accessibilityValue: String {
        if chat.isProvisional {
            return "\(chat.preview), Review Import"
        }
        return "\(chat.preview), \(persona.name) persona"
    }
}

private struct ChatPersonaBadge: View {
    let persona: Persona

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: persona.symbolName)
                .font(.system(size: 10, weight: .semibold))

            Text(verbatim: persona.name)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .tracking(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(persona.accent.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(persona.accent.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(persona.accent.opacity(0.16), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ChatActivityDateStyle: Equatable {
    case time
    case weekday
    case monthDay
    case shortDate
}

enum ChatActivityDateFormatter {
    static func style(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> ChatActivityDateStyle {
        if calendar.isDate(date, inSameDayAs: now) {
            return .time
        }

        let activityDay = calendar.startOfDay(for: date)
        let currentDay = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: activityDay, to: currentDay).day
        if let daysAgo, (1...6).contains(daysAgo) {
            return .weekday
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return .monthDay
        }

        return .shortDate
    }

    static func text(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone

        switch style(for: date, relativeTo: now, calendar: calendar) {
        case .time:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .weekday:
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        case .monthDay:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        case .shortDate:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }

        return formatter.string(from: date)
    }
}
