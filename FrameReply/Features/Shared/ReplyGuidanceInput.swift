import SwiftUI

struct ReplyGuidanceInput: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let dictation: GuidanceDictation
    var isDisabled = false
    var isMultiline = false
    let identifier: String

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: TextSelection?
    @State private var editAfterDictation = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            editor
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FrameReplyColor.onSurface)
                .disabled(isDisabled || dictation.isActive)
                .overlay {
                    if dictation.isActive {
                        Button(action: stopAndEdit) {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(AppStrings.Dictation.stopAndEdit))
                        .accessibilityValue(Text(verbatim: text))
                    }
                }

            Button {
                if dictation.isActive {
                    stopAndEdit()
                } else {
                    start()
                }
            } label: {
                Group {
                    if dictation.isActive && dictation.phase != .listening {
                        ProgressView()
                    } else {
                        Image(systemName: "mic")
                            .font(.system(size: 20, weight: .medium))
                    }
                }
                .foregroundStyle(
                    dictation.phase == .listening ? .white : FrameReplyColor.onSurfaceVariant
                )
                .frame(width: 36, height: 36)
                .background {
                    if dictation.phase == .listening {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .foregroundStyle(FrameReplyColor.actionFill)
                            .symbolEffect(.breathe.plain, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || dictation.phase == .finishing)
            .accessibilityLabel(
                Text(microphoneLabel)
            )
            .accessibilityHint(
                Text(
                    dictation.isActive
                        ? AppStrings.Dictation.activeMicrophoneHint
                        : AppStrings.Dictation.microphoneHint)
            )
            .accessibilityAddTraits(dictation.phase == .listening ? [.isSelected] : [])
            .accessibilityValue(
                Text(speechLanguage.label)
            )
            .accessibilityIdentifier("\(identifier)-microphone")
            .contextMenu {
                if dictation.isActive {
                    Button {
                        dictation.cancel(discard: true)
                    } label: {
                        Label {
                            Text(AppStrings.Dictation.discard)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .onChange(of: dictation.text) { _, value in
            selection = nil
            text = value
        }
        .onChange(of: dictation.phase) { _, phase in
            if phase == .idle, editAfterDictation {
                editAfterDictation = false
                isFocused = true
            }
        }
        .onChange(of: text) { _, value in
            // Another surface can replace the shared draft while setup is pending.
            if dictation.isActive, value != dictation.text {
                dictation.cancel()
            }
        }
        .onChange(of: isDisabled) { _, disabled in
            if disabled { endSession() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { endSession() }
        }
        .onDisappear { endSession() }
    }

    private var speechLanguage: GuidanceSpeechLanguage {
        GuidanceSpeechLanguage.resolve(
            appLanguage: LocalizationContext.current.languageIdentifier)
    }

    private var microphoneLabel: LocalizedStringResource {
        switch dictation.phase {
        case .idle: AppStrings.Dictation.start
        case .preparing: AppStrings.Dictation.preparing
        case .downloading: AppStrings.Dictation.downloading
        case .listening: AppStrings.Dictation.stop
        case .finishing: AppStrings.Dictation.finishing
        }
    }

    @ViewBuilder private var editor: some View {
        if isMultiline {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Add reply guidance…")
                        .foregroundStyle(FrameReplyColor.onSurfaceVariant.opacity(0.72))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                textEntry(TextEditor(text: editableText, selection: $selection))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 160 : 84)
            }
        } else {
            textEntry(
                TextField(
                    "Add reply guidance…", text: editableText, selection: $selection,
                    axis: .vertical
                )
            )
            .lineLimit(1...3)
            .submitLabel(.return)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func textEntry<Editor: View>(_ editor: Editor) -> some View {
        editor
            .focused($isFocused)
            .accessibilityLabel("Reply Guidance")
            .accessibilityHint(
                "One-use context, direction, tone, or a rough draft for the next replies."
            )
            .accessibilityIdentifier(identifier)
    }

    private var editableText: Binding<String> {
        Binding(
            get: { text },
            set: { value in
                guard !dictation.isActive else { return }
                // A long transcript remains visible and can be shortened before use.
                guard DraftingInputLimits.canAccept(value) || value.count < text.count else {
                    return
                }
                text = value
            })
    }

    private func start() {
        let range: Range<String.Index>?
        if let selection, case .selection(let selectedRange) = selection.indices {
            range = selectedRange
        } else {
            range = nil
        }
        let draft = GuidanceDictationDraft(text: text, selection: range)
        isFocused = false
        selection = nil
        editAfterDictation = false
        dictation.start(draft: draft, locale: speechLanguage.locale)
    }

    private func stopAndEdit() {
        editAfterDictation = true
        dictation.stop()
    }

    private func endSession() {
        editAfterDictation = false
        selection = nil
        if dictation.isActive {
            text = dictation.text
            dictation.cancel()
        }
    }
}

struct ReplyGuidanceDictationStatus: View {
    let dictation: GuidanceDictation
    let text: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dictation.phase == .downloading {
                Text(AppStrings.Dictation.downloading)
            }
            if !DraftingInputLimits.canAccept(text) {
                Text(AppStrings.Dictation.tooLong)
                    .foregroundStyle(.red)
            }
            if let error = dictation.error {
                Text(error)
                if dictation.microphoneDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(FrameReplyColor.onSurfaceVariant)
        .fixedSize(horizontal: false, vertical: true)
    }

}

enum GuidanceSpeechLanguage {
    case english
    case mandarin

    static func resolve(appLanguage: String) -> Self {
        appLanguage.hasPrefix("zh") ? .mandarin : .english
    }

    var locale: Locale {
        switch self {
        case .english:
            Locale(
                identifier: Locale.preferredLanguages.first(where: { $0.hasPrefix("en") })
                    ?? "en-US")
        case .mandarin:
            Locale(identifier: "zh-CN")
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .english: AppStrings.Dictation.english
        case .mandarin: AppStrings.Dictation.mandarin
        }
    }
}
