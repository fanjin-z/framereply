#!/usr/bin/env bash
# run.sh — Build and launch zeptly in the iOS Simulator without opening Xcode.
#
# Usage:
#   ./run.sh                       # preserve app data; use iPhone 17
#   ./run.sh "iPhone 16"           # preserve app data; override simulator name
#   ./run.sh --reset-data          # clear app data before reinstalling
#   ./run.sh --reset-data "iPhone 16"

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

# ── 1. Resolve a booted or available simulator ─────────────────────────────
echo "▸ Looking for simulator: $SIMULATOR_NAME"
SIM_ID=$(xcrun simctl list devices available --json \
  | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
name = '$SIMULATOR_NAME'

def runtime_version(rt):
    # Extract numeric version tuple from runtime identifier or display string
    # e.g. 'com.apple.CoreSimulator.SimRuntime.iOS-26-3' -> (26, 3)
    m = re.search(r'[Ii][Oo][Ss][^0-9]*([0-9]+)[\-\.]([0-9]+)', rt)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    return (0, 0)

candidates = []
for runtime, devices in data['devices'].items():
    is_ios = 'iOS' in runtime or 'com.apple.CoreSimulator.SimRuntime.iOS' in runtime
    if not is_ios:
        continue
    for d in devices:
        if d['name'] == name and d['isAvailable']:
            candidates.append((runtime_version(runtime), d['state'] == 'Booted', d))

if not candidates:
    print('NOT_FOUND')
else:
    # Sort by (latest iOS version, booted first)
    candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print(candidates[0][2]['udid'])
")

if [[ "$SIM_ID" == "NOT_FOUND" ]]; then
  echo "✗ No available simulator named \"$SIMULATOR_NAME\"."
  echo "  Available iOS simulators:"
  xcrun simctl list devices available | grep -E "iPhone|iPad" | head -20
  exit 1
fi

echo "  Simulator UDID: $SIM_ID"

# ── 2. Boot the simulator if it isn't already running ──────────────────────
SIM_STATE=$(xcrun simctl list devices --json \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for devices in data['devices'].values():
    for d in devices:
        if d['udid'] == '$SIM_ID':
            print(d['state'])
            sys.exit(0)
print('Unknown')
")

if [[ "$SIM_STATE" != "Booted" ]]; then
  echo "▸ Booting simulator..."
  xcrun simctl boot "$SIM_ID"
fi

# Open the Simulator.app so the window is visible
open -a Simulator --args -CurrentDeviceUDID "$SIM_ID"

# ── 3. Build ───────────────────────────────────────────────────────────────
echo "▸ Building $SCHEME..."
if command -v xcpretty &>/dev/null; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -configuration Debug \
    build 2>&1 | xcpretty
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -configuration Debug \
    build
fi

# ── 4. Find the built .app bundle ─────────────────────────────────────────
APP_PATH=$(find "$DERIVED_DATA_DIR" -name "zeptly.app" -path "*/Debug-iphonesimulator/*" | head -1)
if [[ -z "$APP_PATH" ]]; then
  echo "✗ Could not locate built zeptly.app under $DERIVED_DATA_DIR"
  exit 1
fi
echo "  App bundle: $APP_PATH"

# ── 5. Stop the existing app and optionally reset its data ─────────────────
if xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" app &>/dev/null; then
  echo "▸ Stopping existing app..."
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true

  if [[ "$RESET_DATA" == true ]]; then
    echo "▸ Resetting app data..."
    xcrun simctl uninstall "$SIM_ID" "$BUNDLE_ID"
  fi
elif [[ "$RESET_DATA" == true ]]; then
  echo "▸ No existing app data to reset."
fi

# ── 6. Install & launch ───────────────────────────────────────────────────
echo "▸ Installing on simulator..."
xcrun simctl install "$SIM_ID" "$APP_PATH"

echo "▸ Launching $BUNDLE_ID..."
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"

echo "✓ Done — zeptly is running in the simulator."
