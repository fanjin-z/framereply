# Zeptly

Zeptly is an open-source AI reply assistant for context-aware communication.

## Status

Zeptly is in early preview.

## Requirements

- macOS with Xcode installed.
- iOS Simulator.

## Quick Start

```bash
git clone git@github.com:fanjin-z/zeptly.git
cd zeptly
./run.sh
```

By default, `run.sh` builds and launches the app on an `iPhone 17` simulator. You can pass another simulator name if needed:

```bash
./run.sh "iPhone 16"
```

## Import Chats

### In Zeptly

Tap **Add Messages** to choose up to eight screenshots or paste message text.

### With Shortcuts

Add either workflow from **Zeptly → Settings → Shortcuts**.

#### Images

1. Tap **Add Image Shortcut** to install **Zeptly Images**.
2. Run it to capture the conversation currently on screen.
3. To import saved images, select 1–8 images from the same conversation in Photos, then tap **Share → Zeptly Images**.

```text
Shared images ──┐
                ├→ Analyze → Generate replies → Show result
Take screenshot ┘
```

#### Text

1. Tap **Add Text Shortcut** to install **Zeptly Text**.
2. If your chat app can share selected messages as plain text, tap **Share → Zeptly Text**.
3. Otherwise, copy the messages and run **Zeptly Text**.

```text
Shared text ──┐
              ├→ Analyze → Generate replies → Show result
Get Clipboard ┘
```

Run either shortcut from Spotlight, Siri, the Action button, Back Tap, the Home Screen, or the Shortcuts app.

### Notes

- Text import accepts up to 8,000 characters, 40 text items, and approximately 25 messages.
- Images and message text are sent transiently to the selected model provider. Zeptly stores extracted messages, not source images or raw imported text.
- Imports with uncertain ownership are saved in **Review Imports**; Zeptly still attempts to generate replies.
- Early-preview shortcuts using **Analyze Chat Screenshot** must be replaced with **Zeptly Images**.

See [Shortcut maintenance and troubleshooting](docs/shortcuts.md) for the exact workflows, publishing checklist, recovery process, and Back Tap guidance.

## Contributing

Contributions are welcome once contribution guidelines are added. Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in Zeptly are provided under the Apache License 2.0.

## License

Zeptly is licensed under the [Apache License 2.0](LICENSE).
