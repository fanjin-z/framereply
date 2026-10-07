//
//  ChatMessageBubble.swift
//  FrameReply
//

import SwiftUI
import Translation

enum ChatMessageBubbleStyle {
    static func background(for message: ChatMessage) -> Color {
        if message.isSenderUnknown {
            return FrameReplyColor.surfaceVariant.opacity(0.9)
        }
        return message.isFromUser
            ? FrameReplyColor.primaryFixed.opacity(0.72) : FrameReplyColor.incomingMessageBubble
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage
    let translation: ChatHistoryTranslation
    let translationKey: ChatHistoryTranslation.Key

    @Environment(\.locale) private var locale
    @State private var request: ChatHistoryTranslation.Request?
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        HStack {
            if message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 52)
            }

            VStack(alignment: contentAlignment, spacing: 6) {
                originalMessage
                if let state = translation.states[translationKey] {
                    Divider()
                    translationContent(state)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 360, alignment: frameAlignment)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ChatMessageBubbleStyle.background(for: message))
                    .shadow(
                        color: FrameReplyColor.primaryContainer.opacity(0.08), radius: 14, x: 0,
                        y: 8)
            }
            .contextMenu {
                if case .translating = translation.states[translationKey] {
                    Button("Cancel translation", systemImage: "xmark", action: hideTranslation)
                } else {
                    Button("Translate", systemImage: "translate", action: translate)
                        .disabled(
                            message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if translation.states[translationKey] != nil {
                        Button(
                            "Hide translation", systemImage: "eye.slash", action: hideTranslation)
                    }
                }
            }
            .translationTask(configuration) { session in
                guard let request else { return }
                await performTranslation(request, using: session)
            }
            .onDisappear {
                if let request { translation.cancel(request) }
                request = nil
                configuration = nil
            }

            if !message.isFromUser || message.isSenderUnknown {
                Spacer(minLength: 52)
            }
        }
    }

    private var originalMessage: some View {
        VStack(alignment: contentAlignment, spacing: 6) {
            if message.isSenderUnknown {
                Label("Sender unknown", systemImage: "questionmark.circle.fill")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(FrameReplyColor.primary)
            }
            Text(verbatim: message.text)
                .font(.system(.subheadline, design: .rounded, weight: .regular))
                .foregroundStyle(FrameReplyColor.onSurface)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if !message.timeLabel.isEmpty {
                Text(verbatim: message.timeLabel)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(FrameReplyColor.outline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: message.accessibilityDescription))
        .accessibilityAction(named: Text("Translate"), translate)
    }

    private func translationContent(_ state: ChatHistoryTranslation.State) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .translating:
                ProgressView("Translating…")
                    .controlSize(.small)
                Button("Cancel translation", action: hideTranslation)
            case .translated(let text):
                Text("Translation · \(targetLanguageName)")
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                Text(verbatim: text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(FrameReplyColor.onSurface)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Hide translation", action: hideTranslation)
            case .failed(let failure):
                Text(failure.message)
                    .foregroundStyle(FrameReplyColor.onSurfaceVariant)
                HStack(spacing: 16) {
                    Button("Try again", action: translate)
                    Button("Hide translation", action: hideTranslation)
                }
            }
        }
        .font(.system(.caption, design: .rounded, weight: .medium))
        .buttonStyle(.borderless)
        .tint(FrameReplyColor.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetLanguageName: String {
        ChatTranslationSupport.languageName(translationKey.targetLanguageIdentifier, locale: locale)
    }

    private func translate() {
        guard let nextRequest = translation.begin(translationKey) else { return }
        request = nextRequest
        if configuration == nil {
            configuration = ChatTranslationSupport.configuration(
                target: Locale.Language(identifier: translationKey.targetLanguageIdentifier)
            )
        } else {
            configuration?.invalidate()
        }
    }

    private func hideTranslation() {
        translation.hide(translationKey)
        request = nil
        configuration = nil
    }

    private func performTranslation(
        _ request: ChatHistoryTranslation.Request, using session: TranslationSession
    ) async {
        defer {
            if self.request == request {
                self.request = nil
                configuration = nil
            }
        }
        #if targetEnvironment(simulator)
            translation.fail(request, reason: .unavailable)
        #else
            do {
                // An inconclusive language check must still allow Apple's source-language prompt.
                let status = try? await ChatTranslationSupport.availability().status(
                    for: request.key.sourceText,
                    to: Locale.Language(identifier: request.key.targetLanguageIdentifier)
                )
                try Task.checkCancellation()
                guard translation.isTranslating(request) else { return }
                guard status != .unsupported else {
                    translation.fail(request, reason: .unsupportedLanguage)
                    return
                }
                // The view-bound session can ask permission to download missing language models.
                let response = try await session.translate(request.key.sourceText)
                try Task.checkCancellation()
                translation.finish(request, text: response.targetText)
            } catch is CancellationError {
                translation.cancel(request)
            } catch TranslationError.alreadyCancelled {
                translation.cancel(request)
            } catch TranslationError.unsupportedSourceLanguage,
                TranslationError.unsupportedTargetLanguage,
                TranslationError.unsupportedLanguagePairing
            {
                translation.fail(request, reason: .unsupportedLanguage)
            } catch {
                if Task.isCancelled {
                    translation.cancel(request)
                } else {
                    translation.fail(request, reason: .failed)
                }
            }
        #endif
    }

    private var contentAlignment: HorizontalAlignment {
        message.isSenderUnknown ? .center : (message.isFromUser ? .trailing : .leading)
    }

    private var frameAlignment: Alignment {
        message.isSenderUnknown ? .center : (message.isFromUser ? .trailing : .leading)
    }
}
