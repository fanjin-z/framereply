#!/usr/bin/env bash
# run.sh — Build and launch zeptly on a connected iPhone or iOS Simulator.
#
# Usage:
#   ./run.sh                       # prefer one connected iPhone; otherwise use iPhone 17
#   ./run.sh "iPhone 16"           # explicitly use this simulator
#   ./run.sh --reset-data "iPhone 16"  # clear simulator app data before reinstalling

set -euo pipefail

PROJECT="zeptly.xcodeproj"
SCHEME="zeptly"
BUNDLE_ID="com.gigabeyond.zeptly"
DERIVED_DATA_DIR="$(pwd)/.build/DerivedData"
RESET_DATA=false
SIMULATOR_NAME="iPhone 17"
SIMULATOR_NAME_SET=false

usage() {
  echo "Usage: ./run.sh [--reset-data] [simulator name]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset-data)
      RESET_DATA=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "✗ Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ "$SIMULATOR_NAME_SET" == true ]]; then
        echo "✗ Only one simulator name may be provided."
        usage
        exit 1
      fi
      SIMULATOR_NAME="$1"
      SIMULATOR_NAME_SET=true
      ;;
  esac
  shift
done

# ── 1. Prefer one connected physical iPhone unless a simulator was named ───
TARGET_KIND="simulator"
TARGET_ID=""
TARGET_NAME="$SIMULATOR_NAME"

if [[ "$SIMULATOR_NAME_SET" == false ]]; then
  DEVICE_JSON=$(mktemp "${TMPDIR:-/tmp}/zeptly-devices.XXXXXX")
  trap 'rm -f "$DEVICE_JSON"' EXIT
  xcrun devicectl list devices --json-output "$DEVICE_JSON" --quiet

  PHYSICAL_DEVICES=$(python3 - "$DEVICE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    devices = json.load(source).get("result", {}).get("devices", [])

for device in devices:
    connection = device.get("connectionProperties", {})
    hardware = device.get("hardwareProperties", {})
    properties = device.get("deviceProperties", {})
    if (
        connection.get("pairingState") == "paired"
        and connection.get("tunnelState") == "connected"
        and hardware.get("reality") == "physical"
        and hardware.get("platform") == "iOS"
        and hardware.get("deviceType") == "iPhone"
    ):
        print(f"{hardware.get('udid', '')}\t{properties.get('name', 'Connected iPhone')}")
PY
)

  PHYSICAL_DEVICE_COUNT=$(printf '%s\n' "$PHYSICAL_DEVICES" | awk 'NF { count++ } END { print count + 0 }')
  if [[ "$PHYSICAL_DEVICE_COUNT" -gt 1 ]]; then
    echo "✗ Multiple physical iPhones are connected:"
    while IFS=$'\t' read -r DEVICE_ID DEVICE_NAME; do
      [[ -n "$DEVICE_ID" ]] && echo "  $DEVICE_NAME ($DEVICE_ID)"
    done <<< "$PHYSICAL_DEVICES"
    echo "  Disconnect all but one, or provide a simulator name explicitly."
    exit 1
  elif [[ "$PHYSICAL_DEVICE_COUNT" -eq 1 ]]; then
    IFS=$'\t' read -r TARGET_ID TARGET_NAME <<< "$PHYSICAL_DEVICES"
    TARGET_KIND="device"
  fi
fi

if [[ "$TARGET_KIND" == "device" && "$RESET_DATA" == true ]]; then
  echo "✗ --reset-data is not supported for physical iPhones."
  echo "  To reset a simulator instead, run: ./run.sh --reset-data \"iPhone 17\""
  exit 1
fi

# ── 2. Resolve and prepare the selected target ─────────────────────────────
if [[ "$TARGET_KIND" == "device" ]]; then
  echo "▸ Using physical iPhone: $TARGET_NAME"
  echo "  Device UDID: $TARGET_ID"
  DESTINATION="platform=iOS,id=$TARGET_ID"
  PRODUCT_DIRECTORY="Debug-iphoneos"
else
  echo "▸ Looking for simulator: $SIMULATOR_NAME"
  TARGET_ID=$(SIMULATOR_NAME="$SIMULATOR_NAME" python3 -c '
import json
import os
import re
import sys

data = json.load(sys.stdin)
name = os.environ["SIMULATOR_NAME"]

def runtime_version(runtime):
    match = re.search(r"[Ii][Oo][Ss][^0-9]*([0-9]+)[-.]([0-9]+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)

candidates = []
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime and "com.apple.CoreSimulator.SimRuntime.iOS" not in runtime:
        continue
    for device in devices:
        if device["name"] == name and device["isAvailable"]:
            candidates.append((runtime_version(runtime), device["state"] == "Booted", device))

if not candidates:
    print("NOT_FOUND")
else:
    candidates.sort(key=lambda candidate: (candidate[0], candidate[1]), reverse=True)
    print(candidates[0][2]["udid"])
' < <(xcrun simctl list devices available --json))

  if [[ "$TARGET_ID" == "NOT_FOUND" ]]; then
    echo "✗ No available simulator named \"$SIMULATOR_NAME\"."
    echo "  Available iOS simulators:"
    xcrun simctl list devices available | grep -E "iPhone|iPad" | head -20
    exit 1
  fi

  echo "  Simulator UDID: $TARGET_ID"
  SIM_STATE=$(SIMULATOR_ID="$TARGET_ID" python3 -c '
import json
import os
import sys

data = json.load(sys.stdin)
for devices in data["devices"].values():
    for device in devices:
        if device["udid"] == os.environ["SIMULATOR_ID"]:
            print(device["state"])
            sys.exit(0)
print("Unknown")
' < <(xcrun simctl list devices --json))

  if [[ "$SIM_STATE" != "Booted" ]]; then
    echo "▸ Booting simulator..."
    xcrun simctl boot "$TARGET_ID"
  fi

  open -a Simulator --args -CurrentDeviceUDID "$TARGET_ID"
  DESTINATION="platform=iOS Simulator,id=$TARGET_ID"
  PRODUCT_DIRECTORY="Debug-iphonesimulator"
fi

# ── 3. Build ───────────────────────────────────────────────────────────────
BUILD_ARGUMENTS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_DIR"
  -configuration Debug
)
if [[ "$TARGET_KIND" == "device" ]]; then
  BUILD_ARGUMENTS+=( -allowProvisioningUpdates )
fi

echo "▸ Building $SCHEME for $TARGET_NAME..."
if command -v xcpretty &>/dev/null; then
  xcodebuild "${BUILD_ARGUMENTS[@]}" build 2>&1 | xcpretty
else
  xcodebuild "${BUILD_ARGUMENTS[@]}" build
fi

# ── 4. Find the target-specific app bundle ─────────────────────────────────
APP_PATH=$(find "$DERIVED_DATA_DIR/Build/Products/$PRODUCT_DIRECTORY" -maxdepth 1 -name "zeptly.app" -print -quit)
if [[ -z "$APP_PATH" ]]; then
  echo "✗ Could not locate $PRODUCT_DIRECTORY/zeptly.app under $DERIVED_DATA_DIR"
  exit 1
fi
echo "  App bundle: $APP_PATH"

# ── 5. Install and launch ──────────────────────────────────────────────────
if [[ "$TARGET_KIND" == "device" ]]; then
  echo "▸ Installing on $TARGET_NAME..."
  xcrun devicectl device install app --device "$TARGET_ID" "$APP_PATH"

  echo "▸ Launching $BUNDLE_ID on $TARGET_NAME..."
  if ! xcrun devicectl device process launch --device "$TARGET_ID" --terminate-existing "$BUNDLE_ID"; then
    echo "✗ Zeptly was installed, but could not be launched."
    echo "  Unlock $TARGET_NAME and run ./run.sh again."
    exit 1
  fi
  echo "✓ Done — zeptly is running on $TARGET_NAME."
else
  if xcrun simctl get_app_container "$TARGET_ID" "$BUNDLE_ID" app &>/dev/null; then
    echo "▸ Stopping existing app..."
    xcrun simctl terminate "$TARGET_ID" "$BUNDLE_ID" 2>/dev/null || true

    if [[ "$RESET_DATA" == true ]]; then
      echo "▸ Resetting app data..."
      xcrun simctl uninstall "$TARGET_ID" "$BUNDLE_ID"
    fi
  elif [[ "$RESET_DATA" == true ]]; then
    echo "▸ No existing app data to reset."
  fi

  echo "▸ Installing on simulator..."
  xcrun simctl install "$TARGET_ID" "$APP_PATH"

  echo "▸ Launching $BUNDLE_ID..."
  xcrun simctl launch "$TARGET_ID" "$BUNDLE_ID"
  echo "✓ Done — zeptly is running in the simulator."
fi
