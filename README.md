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

## Screenshot Shortcut

Zeptly's recommended shortcut is **Capture with Zeptly**. Install it from the **Screenshot Shortcut** card in Zeptly's Settings, then run it from Shortcuts, Siri, the Action button, Back Tap, or another supported system surface. It performs two actions:

1. **Take Screenshot**
2. **Process Chat Screenshot**

The Zeptly action automatically shows a native result dialog with two suggested replies. It also returns a JSON string for advanced automation, including the replies, chat/import IDs, message count, reply status, and a privacy-safe diagnostic reference. Screenshot import remains successful if reply generation is temporarily unavailable.

Until the canonical installer link is configured, create the shortcut manually using the same two actions. **Show Result** and **Quick Look** are unnecessary unless you explicitly want to inspect the raw JSON output.

### Maintainer notes

- Publish the canonical shortcut from a team-controlled Apple account and set its iCloud URL in `ScreenshotShortcutConfiguration.canonicalURLString`.
- Test the public link before each release. Use **Stop Sharing** in Shortcuts when the link must be revoked; deleting the local shortcut is not the revocation workflow.

To keep a signed recovery backup:

1. Open **Capture with Zeptly** in Shortcuts and choose **Share**.
2. Choose **Options → File → Anyone**, then save the exported `.shortcut` file to secure team storage outside the app bundle.
3. Re-export the file whenever the workflow changes and verify that another device can import it.

## Contributing

Contributions are welcome once contribution guidelines are added. Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in Zeptly are provided under the Apache License 2.0.

## License

Zeptly is licensed under the [Apache License 2.0](LICENSE).
