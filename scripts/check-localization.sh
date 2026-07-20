#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift_source_root=${FRAME_REPLY_SWIFT_SOURCE_ROOT:-"$repository_root/FrameReply"}
catalog=${FRAME_REPLY_LOCALIZATION_CATALOG:-"$swift_source_root/Localizable.xcstrings"}
project=${FRAME_REPLY_LOCALIZATION_PROJECT:-"$repository_root/FrameReply.xcodeproj/project.pbxproj"}
app_strings=${FRAME_REPLY_APP_STRINGS:-"$swift_source_root/Models/AppStrings.swift"}
validator="$repository_root/scripts/validate-string-catalog.py"
compile_output=$(mktemp -d "${TMPDIR:-/tmp}/framereply-localization.XXXXXX")
trap 'rm -rf "$compile_output"' EXIT HUP INT TERM

if [ "${1:-}" = "--self-test" ]; then
    python3 "$validator" --catalog "$catalog" --self-test
    exit 0
fi

jq empty "$catalog"
xcrun xcstringstool print "$catalog" >/dev/null
xcrun xcstringstool compile "$catalog" --output-directory "$compile_output" >/dev/null

if [ ! -f "$app_strings" ]; then
    echo "AppStrings.swift is required for semantic localization keys." >&2
    exit 1
fi

if rg -n '(==|!=|contains|hasPrefix|hasSuffix).*"Imported Chat"|"Imported Chat".*(==|!=|contains|hasPrefix|hasSuffix)' \
    "$swift_source_root" --glob '*.swift'; then
    echo "Localized fallback text must not be used as identity or state." >&2
    exit 1
fi

if rg -n 'count[[:space:]]*==[[:space:]]*1.*(message|messages)|\?[[:space:]]*"message"[[:space:]]*:[[:space:]]*"messages"' \
    "$swift_source_root" --glob '*.swift' \
    --glob '!**/Services/ChatScreenshotPrompt.swift'; then
    echo "User-facing counts must use String Catalog plural variants." >&2
    exit 1
fi

source_language=$(jq -r '.sourceLanguage' "$catalog")
if [ -n "${FRAME_REPLY_SUPPORTED_LANGUAGES:-}" ]; then
    project_languages=$FRAME_REPLY_SUPPORTED_LANGUAGES
else
    project_languages=$(
        plutil -convert json -o - "$project" \
            | jq -r '.objects[] | select(.isa == "PBXProject") | .knownRegions[] | select(. != "Base")' \
            | sort -u
    )
fi

if ! printf '%s\n' "$project_languages" | rg -qx "$source_language"; then
    echo "Source language $source_language is not registered in the Xcode project." >&2
    exit 1
fi

supported_languages=$(printf '%s\n' "$project_languages" | paste -sd, -)
python3 "$validator" --catalog "$catalog" --languages "$supported_languages"

semantic_keys=$(
    jq -r '.strings | keys[] | select(test("^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+$"))' \
        "$catalog"
)
for key in $semantic_keys; do
    if ! rg -Fq "\"$key\"" "$app_strings"; then
        echo "Semantic localization key is missing from AppStrings: $key" >&2
        exit 1
    fi
    if rg -n -F "\"$key\"" "$swift_source_root" --glob '*.swift' \
        --glob '!**/Models/AppStrings.swift'; then
        echo "Raw semantic localization key must be referenced through AppStrings: $key" >&2
        exit 1
    fi
done

echo "Localization checks passed."
