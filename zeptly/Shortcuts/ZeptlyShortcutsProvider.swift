//
//  ZeptlyShortcutsProvider.swift
//  zeptly
//

import AppIntents

struct ZeptlyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeChatScreenshotIntent(),
            phrases: [
                "Analyze chat screenshot in \(.applicationName)",
                "Analyze my chat screenshot with \(.applicationName)"
            ],
            shortTitle: "Analyze Chat Screenshot",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: GenerateSuggestedRepliesIntent(),
            phrases: ["Generate suggested replies with \(.applicationName)"],
            shortTitle: "Generate Suggested Replies",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: AnalyzeCopiedMessagesIntent(),
            phrases: ["Analyze copied messages with \(.applicationName)"],
            shortTitle: "Analyze Copied Messages",
            systemImageName: "doc.on.clipboard"
        )
    }
}
