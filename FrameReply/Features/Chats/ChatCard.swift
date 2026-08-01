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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 48

    var body: some View {
        Button(action: onChatTap) {
            HStack(alignment: .top, spacing: 12) {
                avatar
                details
                activityLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Chat Assistant for \(chat.name)")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("chat-card-\(chat.id)")
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .frame(minHeight: 84)
    }

    private var avatar: some View {
        AvatarMark(
            initials: chat.initials,
            symbolName: chat.avatarSymbol,
            colors: chat.gradient,
            size: min(avatarSize, 60)
        )
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chat.name)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineLimit(textLineLimit)
                .layoutPriority(2)

            Text(chat.preview)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurfaceVariant.opacity(0.84))
                .lineLimit(textLineLimit)

            contextBadge
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityLabel: some View {
        Text(activityText)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(FrameReplyColor.outline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHidden(true)
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
            return "\(chat.preview), \(activityText), Review Import"
        }
        return "\(chat.preview), \(activityText), \(persona.name) persona"
    }

    private var activityText: String {
        ChatActivityDateFormatter.text(for: chat.updatedAt)
    }

    private var textLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }
}

private struct ChatPersonaBadge: View {
    let persona: Persona

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: persona.symbolName)
                    .font(.system(size: 10, weight: .semibold))

                Text(verbatim: persona.name)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(persona.accent.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(persona.accent.opacity(0.11))
            }

            Spacer(minLength: 0)
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
