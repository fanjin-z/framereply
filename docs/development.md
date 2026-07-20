# Development Guide

This guide contains the local setup and validation steps for contributors. Read [CONTRIBUTING.md](../CONTRIBUTING.md) before submitting changes.

## Prerequisites

- macOS with Xcode 26.6 or a compatible newer release.
- An iOS 26 simulator, or an iPhone or iPad running iOS/iPadOS 26 for device-only behavior.
- Git and the Xcode command-line tools.
- [pre-commit](https://pre-commit.com/) for the repository hooks.

A user-owned supported provider API key is needed only to exercise live AI analysis and reply generation. Provider usage may incur charges billed by that provider.

## Local configuration

Clone the repository and create the ignored local signing configuration:

```bash
git clone git@github.com:fanjin-z/framereply.git
cd framereply
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig` to your Apple Developer Team ID when building for a physical device. Leave it unchanged for unsigned simulator builds. Never commit `Local.xcconfig`, API keys, signing files, or provisioning profiles.

Provider keys are entered in the running app and stored in the device Keychain. Do not add them to source files, schemes, build settings, test fixtures, or screenshots.

## Run from Xcode

1. Open `FrameReply.xcodeproj`.
2. Select the shared **FrameReply** scheme.
3. Choose an iOS 26 simulator or a configured physical device.
4. Choose **Product → Run**.

A simulator build does not require a signing identity. Shortcuts, App Intents, Keychain behavior, and release entitlements should also be verified on a physical device before release.

## Command-line build

Build the app for a generic iOS simulator without code signing:

```bash
xcodebuild build \
  -project FrameReply.xcodeproj \
  -scheme FrameReply \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Tests

The shared scheme includes the unit and UI test targets. Run them from **Product → Test** in Xcode, or target an installed simulator from the command line:

```bash
xcodebuild test \
  -project FrameReply.xcodeproj \
  -scheme FrameReply \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

If that simulator is unavailable, list installed devices with `xcrun simctl list devices available` and substitute an available iOS 26 simulator name.

Tests, documentation, and screenshots must use synthetic identities and conversations. Never copy a real chat into a fixture or failure attachment.

## Formatting and repository checks

Install the repository hooks once:

```bash
pre-commit install
```

Run all configured hooks before submitting a broad Swift change:

```bash
pre-commit run --all-files
```

The hooks format and lint Swift files using the repository's `.swift-format` configuration.

For localization changes, run both the production check and its fixture tests:

```bash
scripts/check-localization.sh
scripts/test-localization-check.sh
```

When source strings change, build the app so Xcode emits current localization metadata before synchronizing the String Catalog. See the localization rules in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Related documentation

- [Architecture](architecture.md)
- [AI workflows](ai-workflows.md)
- [Shortcut maintenance and troubleshooting](shortcuts.md)
- [Security policy](../SECURITY.md)
