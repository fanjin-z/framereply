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

Zeptly's recommended shortcut is **Capture with Zeptly**. Install it from the **Screenshot Shortcut** card in Zeptly's Settings, then run it from Shortcuts, Siri, the Action button, Back Tap, or another supported system surface. It performs four actions:

1. **Take Screenshot**
2. **Analyze Chat Screenshot**
3. **Generate Suggested Replies**
4. **Show Result**

On iOS 26 or later, **Analyze Chat Screenshot** first offers **Add Context or Draft** and **Skip**. Choosing Add opens a multiline prompt while analysis continues; Done with blank text is also treated as Skip. The system Cancel button stops the Shortcut. On iOS 18–25, the text prompt explains that Done empty skips and Cancel stops. Submitted text is used once and expires after 15 minutes if the workflow is abandoned. **Generate Suggested Replies** waits until that input choice is durably committed, then returns ready-to-display text containing the import status and two replies. Screenshot import remains successful if reply generation is temporarily unavailable.

For Back Tap, turn off **Settings → Accessibility → Touch → Back Tap → Show Banner**. The banner can cover a messaging app's conversation title before the screenshot is taken. The screenshot animation and context input sheet still provide visible confirmation that the shortcut ran; no vibration action is required.

Until the canonical installer link is configured, create the shortcut manually using the same four actions and connect each action to the previous action's output.

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
