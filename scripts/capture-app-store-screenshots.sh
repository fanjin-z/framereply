#!/bin/zsh

set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
readonly PROJECT_PATH="$PROJECT_ROOT/FrameReply.xcodeproj"
readonly SCHEME="FrameReply"
readonly SCREENSHOT_TEST_CLASS="FrameReplyUITests/FrameReplyShowcaseScreenshotTests"
readonly LOCALE="en-US"
readonly DEVICE_FOLDER="iphone-6.9"
readonly -a SCREENSHOT_NAMES=(
  "01-suggested-replies"
  "02-add-messages"
  "03-reply-brief"
  "04-chats"
  "05-personas"
  "06-context-and-rationale"
)
readonly -a DEVICE_PREFERENCES=(
  "iPhone 17 Pro Max"
  "iPhone 16 Pro Max"
  "iPhone 16 Plus"
  "iPhone 15 Pro Max"
  "iPhone 15 Plus"
  "iPhone 14 Pro Max"
)

cd "$PROJECT_ROOT"

marketing_version="$(
  sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
    "$PROJECT_PATH/project.pbxproj" | head -1
)"
if [[ -z "$marketing_version" ]]; then
  print -u2 "Could not determine MARKETING_VERSION."
  exit 1
fi

deployment_target="$(
  sed -n 's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = \([^;]*\);/\1/p' \
    "$PROJECT_PATH/project.pbxproj" | head -1
)"
if [[ -z "$deployment_target" ]]; then
  print -u2 "Could not determine IPHONEOS_DEPLOYMENT_TARGET."
  exit 1
fi

capture_timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_directory="$PROJECT_ROOT/build/app-store-screenshots/$marketing_version/$capture_timestamp/$LOCALE/$DEVICE_FOLDER"
result_bundle="$run_directory/FrameReplyShowcase.xcresult"
attachment_directory="$run_directory/.attachments"
derived_data="$PROJECT_ROOT/build/app-store-screenshots/.derived-data"
mkdir -p "$run_directory" "$derived_data"

device_list_json="$(mktemp -t framereply-simulators.XXXXXX)"
runtime_list_json="$(mktemp -t framereply-runtimes.XXXXXX)"
xcrun simctl list --json devices available > "$device_list_json"
xcrun simctl list --json runtimes > "$runtime_list_json"

device_record=""
for preferred_name in "${DEVICE_PREFERENCES[@]}"; do
  device_record="$(
    jq -r \
      --arg name "$preferred_name" \
      --arg minimum "$deployment_target" \
      --slurpfile runtime_catalog "$runtime_list_json" '
      .devices
      | to_entries
      | map(
          .key as $runtime
          | .value[]
          | select(.name == $name and .isAvailable == true)
          | . as $device
          | $runtime_catalog[0].runtimes[]
          | select(.identifier == $runtime and .isAvailable == true)
          | select(
              (.version | split(".") | map(tonumber))
              >= ($minimum | split(".") | map(tonumber))
            )
          | {
              udid: $device.udid,
              name: $device.name,
              state: $device.state,
              runtime: $runtime,
              runtimeName: .name,
              runtimeVersion: .version
            }
        )
      | sort_by(.runtimeVersion | split(".") | map(tonumber))
      | reverse
      | first // empty
      | @base64
    ' "$device_list_json"
  )"
  [[ -n "$device_record" ]] && break
done
rm -f "$device_list_json" "$runtime_list_json"

if [[ -z "$device_record" ]]; then
  print -u2 "No accepted 6.9-inch simulator is installed."
  print -u2 "Install one of: ${DEVICE_PREFERENCES[*]}"
  exit 1
fi

decode_device_field() {
  print -r -- "$device_record" | base64 --decode | jq -r ".$1"
}

device_udid="$(decode_device_field udid)"
device_name="$(decode_device_field name)"
device_initial_state="$(decode_device_field state)"
runtime_description="$(decode_device_field runtimeName)"

original_appearance=""
original_content_size=""
simulator_booted_by_script=false

restore_simulator() {
  set +e
  xcrun simctl status_bar "$device_udid" clear >/dev/null 2>&1
  if [[ "$original_appearance" == "light" || "$original_appearance" == "dark" ]]; then
    xcrun simctl ui "$device_udid" appearance "$original_appearance" >/dev/null 2>&1
  fi
  if [[ -n "$original_content_size" && "$original_content_size" != "unknown" && "$original_content_size" != "unsupported" ]]; then
    xcrun simctl ui "$device_udid" content_size "$original_content_size" >/dev/null 2>&1
  fi
  if [[ "$simulator_booted_by_script" == true ]]; then
    xcrun simctl shutdown "$device_udid" >/dev/null 2>&1
  fi
}
trap restore_simulator EXIT INT TERM

if [[ "$device_initial_state" != "Booted" ]]; then
  xcrun simctl boot "$device_udid"
  simulator_booted_by_script=true
fi
xcrun simctl bootstatus "$device_udid" -b

original_appearance="$(
  xcrun simctl ui "$device_udid" appearance 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | tail -1 \
    | xargs
)"
original_content_size="$(
  xcrun simctl ui "$device_udid" content_size 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | tail -1 \
    | xargs
)"
xcrun simctl ui "$device_udid" appearance light
xcrun simctl ui "$device_udid" content_size large
xcrun simctl status_bar "$device_udid" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4

print "Capturing six screenshots on $device_name ($runtime_description)…"
xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$device_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_bundle" \
  -only-testing:"$SCREENSHOT_TEST_CLASS"

mkdir -p "$attachment_directory"
xcrun xcresulttool export attachments \
  --path "$result_bundle" \
  --output-path "$attachment_directory"

attachment_manifest="$attachment_directory/manifest.json"
if [[ ! -f "$attachment_manifest" ]]; then
  print -u2 "xcresulttool did not produce an attachment manifest."
  exit 1
fi

for screenshot_name in "${SCREENSHOT_NAMES[@]}"; do
  exported_filename="$(
    jq -r --arg name "$screenshot_name" '
      [
        .[].attachments[]
        | select(
            .suggestedHumanReadableName == $name
            or .suggestedHumanReadableName == ($name + ".png")
            or (.suggestedHumanReadableName | startswith($name + "_"))
          )
        | .exportedFileName
      ]
      | first // empty
    ' "$attachment_manifest"
  )"
  if [[ -z "$exported_filename" || ! -f "$attachment_directory/$exported_filename" ]]; then
    print -u2 "Missing retained attachment: $screenshot_name"
    exit 1
  fi

  cp "$attachment_directory/$exported_filename" "$run_directory/$screenshot_name.png"
  compressed_path="$run_directory/.$screenshot_name.compressed.png"
  xcrun pngcrush -q -rem alla -reduce \
    "$run_directory/$screenshot_name.png" \
    "$compressed_path"
  mv "$compressed_path" "$run_directory/$screenshot_name.png"
done

png_count="$(find "$run_directory" -maxdepth 1 -type f -name '*.png' | wc -l | xargs)"
if [[ "$png_count" != "${#SCREENSHOT_NAMES[@]}" ]]; then
  print -u2 "Expected exactly six final PNG files; found $png_count."
  exit 1
fi

image_records_file="$(mktemp -t framereply-images.XXXXXX)"
: > "$image_records_file"
for screenshot_name in "${SCREENSHOT_NAMES[@]}"; do
  screenshot_path="$run_directory/$screenshot_name.png"
  pixel_width="$(sips -g pixelWidth "$screenshot_path" | awk '/pixelWidth/ { print $2 }')"
  pixel_height="$(sips -g pixelHeight "$screenshot_path" | awk '/pixelHeight/ { print $2 }')"
  has_alpha="$(sips -g hasAlpha "$screenshot_path" | awk '/hasAlpha/ { print tolower($2) }')"

  case "${pixel_width}x${pixel_height}" in
    1260x2736|1290x2796|1320x2868) ;;
    *)
      print -u2 "Unexpected 6.9-inch dimensions for $screenshot_name: ${pixel_width}x${pixel_height}"
      exit 1
      ;;
  esac

  if [[ "$has_alpha" != "no" ]]; then
    print -u2 "$screenshot_name still has an alpha channel."
    exit 1
  fi

  jq -n \
    --arg filename "$screenshot_name.png" \
    --argjson width "$pixel_width" \
    --argjson height "$pixel_height" \
    '{ filename: $filename, width: $width, height: $height }' \
    >> "$image_records_file"
done

commit_sha="$(git rev-parse HEAD)"
git_dirty=false
if [[ -n "$(git status --porcelain)" ]]; then
  git_dirty=true
fi
xcode_version="$(xcodebuild -version | paste -sd ' ' -)"
capture_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

jq -n \
  --arg commit_sha "$commit_sha" \
  --argjson working_tree_dirty "$git_dirty" \
  --arg marketing_version "$marketing_version" \
  --arg xcode_version "$xcode_version" \
  --arg simulator_name "$device_name" \
  --arg simulator_udid "$device_udid" \
  --arg runtime "$runtime_description" \
  --arg locale "$LOCALE" \
  --arg captured_at "$capture_iso" \
  --slurpfile images "$image_records_file" \
  '{
    commit_sha: $commit_sha,
    working_tree_dirty: $working_tree_dirty,
    marketing_version: $marketing_version,
    xcode_version: $xcode_version,
    simulator: {
      name: $simulator_name,
      udid: $simulator_udid,
      runtime: $runtime
    },
    locale: $locale,
    captured_at: $captured_at,
    images: $images
  }' > "$run_directory/manifest.json"
rm -f "$image_records_file"

{
  print '<!doctype html>'
  print '<html lang="en"><head><meta charset="utf-8">'
  print '<meta name="viewport" content="width=device-width,initial-scale=1">'
  print '<title>FrameReply App Store Screenshots</title>'
  print '<style>'
  print 'body{font:16px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:#f5f3fa;color:#24212b}'
  print 'main{max-width:1500px;margin:auto;padding:32px}h1{margin:0 0 8px}.meta{color:#686270;margin-bottom:28px}'
  print '.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px}'
  print 'figure{margin:0;background:#fff;padding:16px;border-radius:20px;box-shadow:0 8px 30px #29202d12}'
  print 'img{display:block;width:100%;height:auto;border-radius:12px}figcaption{font-weight:650;margin-top:12px}'
  print '@media(max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}'
  print '@media(max-width:560px){main{padding:18px}.grid{grid-template-columns:1fr}}'
  print '</style></head><body><main>'
  print '<h1>FrameReply App Store Screenshot Review</h1>'
  print "<p class=\"meta\">$marketing_version · $LOCALE · $device_name · $capture_iso</p>"
  print '<div class="grid">'
  for screenshot_name in "${SCREENSHOT_NAMES[@]}"; do
    title="${screenshot_name%.png}"
    print "<figure><a href=\"$screenshot_name.png\"><img src=\"$screenshot_name.png\" alt=\"$title\"></a><figcaption>$title</figcaption></figure>"
  done
  print '</div></main></body></html>'
} > "$run_directory/index.html"

rm -rf "$attachment_directory"

print "Screenshots captured and validated:"
print "$run_directory"
