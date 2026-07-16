# Zeptly

Zeptly is an open-source iOS and iPadOS AI reply assistant for context-aware communication.

## Requirements

- macOS with Xcode 26.6 or a compatible newer release.
- An iOS 26 simulator or device.
- Your own supported model-provider API key. Provider usage may incur charges billed by that provider.

## Quick start

```bash
git clone git@github.com:fanjin-z/zeptly.git
cd zeptly
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Put your Apple Developer Team ID in Local.xcconfig for device builds.
```

Open `zeptly.xcodeproj`, select the shared `zeptly` scheme and an iOS simulator, then choose **Product → Run**. No signing identity is needed for simulator builds.

For a command-line build:

```bash
xcodebuild build \
  -project zeptly.xcodeproj \
  -scheme zeptly \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Architecture

Start with the contributor [architecture overview](docs/architecture.md), then read [AI workflows](docs/ai-workflows.md) for chat reconciliation and reply-generation design.

## Privacy and provider access

Zeptly has no proxy server, advertising, analytics, or tracking. API keys are stored in the device Keychain. Chats, extracted messages, personas, context, and generated replies are stored in the app's protected local database and excluded from device backups.

Before connecting a provider, Zeptly requires explicit consent to send selected screenshots or text, participant information, context, and drafts directly to that provider. Source images are normalized and are not retained by Zeptly after processing; extracted messages are stored locally. Provider retention and processing are governed by the selected provider's policy. OpenAI requests set `store: false`, but OpenAI may still retain abuse-monitoring data under its API data controls.

See the project [Privacy Policy](docs/privacy.md), [Terms](docs/terms.md), and [Age Suitability](docs/age-suitability.md) pages.

## Import chats

In Zeptly, tap **Add Messages** to choose up to eight still images or paste message text. Images are re-encoded, stripped of metadata, and bounded to 5 MB each and 20 MB per request. Text import accepts 8,000 characters, 40 text items, and approximately 25 messages.

Zeptly also supports two team-published Apple Shortcuts:

- **Zeptly Images** accepts 1–8 shared images or captures the current screen.
- **Zeptly Text** accepts shared text or reads the clipboard when run directly.

Shortcut installation buttons appear only when verified team-owned iCloud links are configured. See [Shortcut maintenance](docs/shortcuts.md).

AI-generated suggestions are drafts. Review them before sending.

## Release and automation

The first App Store release is archived, signed, validated, and submitted manually through Xcode Organizer. The public repository intentionally contains no signing or distribution automation and no App Store credentials.

See the [release runbook](docs/release.md) for the remaining owner-operated checks and safe future automation options.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report vulnerabilities privately according to [SECURITY.md](SECURITY.md); never open a public issue containing credentials, private conversations, or exploitable details.

## License

Zeptly is licensed under the [Apache License 2.0](LICENSE).
