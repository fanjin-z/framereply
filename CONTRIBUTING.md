# Contributing to FrameReply

Thank you for contributing. By submitting a contribution, you agree that it is provided under the Apache License 2.0.

## Local setup

1. Use Xcode 26.6 or a compatible newer version.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and add your own Team ID only when building for a device.
3. Build the shared `FrameReply` scheme in Xcode, or run the unsigned simulator `xcodebuild` command in the README.
4. Run the shared scheme's tests before opening a pull request.
5. Install pre-commit and run `pre-commit install` if you contribute regularly.

Never commit API keys, signing files, provisioning profiles, real conversations, or screenshots containing personal information. Tests and documentation must use synthetic identities and content.

## Pull requests

Keep changes focused, format Swift with the repository configuration, add tests for behavior changes, and explain privacy or data-flow changes explicitly. Do not add signing, distribution, or secret-bearing GitHub Actions workflows.

Update the contributor documentation when changing chat-matching policy, durable learning rules, provider data flow, or the Shortcut handoff contract. Keep architecture documentation focused on concepts and invariants rather than individual implementation files.

## Localization

English is currently the source and only shipped language. All app-owned user-facing copy belongs in `FrameReply/Localizable.xcstrings`.

- Write complete sentences; never concatenate translated fragments.
- Use `LocalizedStringResource` for reusable app-owned labels and render imported, user-authored, provider-brand, and AI reply content explicitly as verbatim text.
- Put reused, programmatic, fallback, error, plural, and interpolated copy in `AppStrings`. Raw semantic catalog keys belong only in that namespace; ordinary one-off SwiftUI literals remain compiler-extracted.
- Keep static App Intents metadata as literals or direct `LocalizedStringResource` initializers at the declaration site; Apple's metadata exporter does not accept indirection through `AppStrings`.
- Add translator comments for ambiguous actions, privacy/consent language, placeholders, interpolated values, and accessibility copy.
- Use String Catalog plural variants for counts.
- Keep protocol tokens, JSON keys, IDs, URLs, model names, logs, diagnostics, and internal prompts out of the catalog.
- Never persist or compare a localized fallback as identity or state.

Run `scripts/check-localization.sh` before submitting a localization-related change. Typed `AppStrings` references protect Swift call sites; the script separately protects catalog integrity and requires every language registered in the Xcode project to be complete and reviewed. When source strings change, build the app so Xcode emits current `.stringsdata`, then sync the catalog with `xcstringstool`.

## Conduct

Be respectful, constructive, and privacy-conscious. Harassment, discrimination, disclosure of another person's private data, and abusive behavior are not accepted. Maintainers may remove content or participation that violates these expectations.
