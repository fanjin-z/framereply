# Contributing to Zeptly

Thank you for contributing. By submitting a contribution, you agree that it is provided under the Apache License 2.0.

## Local setup

1. Use Xcode 26.6 or a compatible newer version.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and add your own Team ID only when building for a device.
3. Build the shared `zeptly` scheme in Xcode, or run the unsigned simulator `xcodebuild` command in the README.
4. Run the shared scheme's tests before opening a pull request.
5. Install pre-commit and run `pre-commit install` if you contribute regularly.

Never commit API keys, signing files, provisioning profiles, real conversations, or screenshots containing personal information. Tests and documentation must use synthetic identities and content.

## Pull requests

Keep changes focused, format Swift with the repository configuration, add tests for behavior changes, and explain privacy or data-flow changes explicitly. Do not add signing, distribution, or secret-bearing GitHub Actions workflows.

Update the contributor documentation when changing chat-matching policy, durable learning rules, provider data flow, or the Shortcut handoff contract. Keep architecture documentation focused on concepts and invariants rather than individual implementation files.

## Conduct

Be respectful, constructive, and privacy-conscious. Harassment, discrimination, disclosure of another person's private data, and abusive behavior are not accepted. Maintainers may remove content or participation that violates these expectations.
