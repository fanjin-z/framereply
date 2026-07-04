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

Create a Shortcut with **Take Screenshot** followed by Zeptly's **Process Screenshot** action. The action automatically shows a native result dialog with two suggested replies and also returns a JSON string for automation, including the replies, chat/import IDs, message count, reply status, and a privacy-safe diagnostic reference. Screenshot import remains successful if reply generation is temporarily unavailable.

Adding **Show Result** or **Quick Look** after Process Screenshot is optional. Use one only when you want to inspect the raw JSON output; it is not required for normal success or failure feedback.

## Contributing

Contributions are welcome once contribution guidelines are added. Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in Zeptly are provided under the Apache License 2.0.

## License

Zeptly is licensed under the [Apache License 2.0](LICENSE).
