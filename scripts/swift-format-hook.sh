#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"
if [[ -z "$mode" ]]; then
    echo "usage: $0 <format|lint> [swift files...]" >&2
    exit 2
fi
shift

swift_format_cmd=()
swift_files=()

for path in "$@"; do
    if [[ -f "$path" && "$path" == *.swift ]]; then
        swift_files+=("$path")
    fi
done

if [[ "${#swift_files[@]}" -eq 0 ]]; then
    exit 0
fi

if swift_format_path="$(xcrun --find swift-format 2>/dev/null)" && [[ -x "$swift_format_path" ]]; then
    swift_format_cmd=("$swift_format_path")
elif command -v swift-format >/dev/null 2>&1; then
    swift_format_cmd=("swift-format")
elif swift format --version >/dev/null 2>&1; then
    swift_format_cmd=("swift" "format")
else
    echo "swift-format was not found. Install Xcode/Swift 6+, or run: brew install swift-format" >&2
    exit 127
fi

case "$mode" in
    format)
        "${swift_format_cmd[@]}" format --in-place --configuration .swift-format "${swift_files[@]}"
        git update-index --again
        ;;
    lint)
        "${swift_format_cmd[@]}" lint --strict --configuration .swift-format "${swift_files[@]}"
        ;;
    *)
        echo "unknown mode: $mode" >&2
        echo "usage: $0 <format|lint> [swift files...]" >&2
        exit 2
        ;;
esac
