#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="$repository_root/scripts/check-localization.sh"
fixture_root="$repository_root/scripts/fixtures/localization"
catalog="$repository_root/FrameReply/Localizable.xcstrings"
project="$repository_root/FrameReply.xcodeproj/project.pbxproj"
app_strings="$repository_root/FrameReply/Models/AppStrings.swift"

"$checker" --self-test

FRAME_REPLY_SWIFT_SOURCE_ROOT="$fixture_root/clean" \
    FRAME_REPLY_LOCALIZATION_CATALOG="$catalog" \
    FRAME_REPLY_LOCALIZATION_PROJECT="$project" \
    FRAME_REPLY_APP_STRINGS="$app_strings" \
    "$checker" >/dev/null

expect_architecture_failure() {
    fixture=$1
    if FRAME_REPLY_SWIFT_SOURCE_ROOT="$fixture_root/$fixture" \
        FRAME_REPLY_LOCALIZATION_CATALOG="$catalog" \
        FRAME_REPLY_LOCALIZATION_PROJECT="$project" \
        FRAME_REPLY_APP_STRINGS="$app_strings" \
        "$checker" >/dev/null 2>&1; then
        echo "Localization architecture fixture unexpectedly passed: $fixture" >&2
        exit 1
    fi
}

expect_architecture_failure raw-semantic-key
expect_architecture_failure localized-sentinel
expect_architecture_failure manual-plural

echo "Localization check self-tests passed."
