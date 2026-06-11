#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$ROOT_DIR/flutter_client"
APP_PATH="$FLUTTER_DIR/build/ios/iphoneos/Runner.app"
BUNDLE_ID="com.qsw.rdesk"

usage() {
  cat <<'EOF'
Usage:
  scripts/reinstall_ios.sh [device-id]

Builds the iOS release app, installs it on a connected iPhone, and launches it.
If device-id is omitted, the first connected iOS device reported by devicectl is used.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEVICE_ID="${1:-}"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICES_JSON="$(mktemp -t rdesk-ios-devices.XXXXXX)"
  xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null
  DEVICE_ID="$(
    python3 - "$DEVICES_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

for device in data.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    properties = device.get("deviceProperties", {})
    connection = device.get("connectionProperties", {})
    if (
        hardware.get("platform") == "iOS"
        and properties.get("bootState") == "booted"
        and connection.get("pairingState") == "paired"
    ):
        print(device.get("identifier", ""))
        break
PY
  )"
  rm -f "$DEVICES_JSON"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iOS device found. Connect and unlock the iPhone, then retry." >&2
  exit 1
fi

echo "Using iOS device: $DEVICE_ID"
echo "Building release app..."
(
  cd "$FLUTTER_DIR"
  flutter build ios --release
)

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce $APP_PATH" >&2
  exit 1
fi

echo "Installing $APP_PATH..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching $BUNDLE_ID..."
LAUNCH_LOG="$(mktemp -t rdesk-ios-launch.XXXXXX)"
if ! xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID" >"$LAUNCH_LOG" 2>&1; then
  cat "$LAUNCH_LOG" >&2
  if grep -q "device was not, or could not be, unlocked\\|BSErrorCodeDescription = Locked" "$LAUNCH_LOG"; then
    echo "Install completed, but launch was blocked because the iPhone is locked. Unlock the iPhone, then run this script again." >&2
  elif grep -q "profile has not been explicitly trusted\\|invalid code signature\\|inadequate entitlements" "$LAUNCH_LOG"; then
    echo "Install completed, but iOS refused to launch it. On the iPhone, open Settings > General > VPN & Device Management and trust the developer profile, then run this script again." >&2
  else
    echo "Install completed, but iOS refused to launch the app. Check the devicectl error above, then run this script again." >&2
  fi
  rm -f "$LAUNCH_LOG"
  exit 2
fi
cat "$LAUNCH_LOG"
rm -f "$LAUNCH_LOG"

echo "Installed app:"
xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null \
  | grep -E "Name|$BUNDLE_ID|Version|Bundle Version" || true

PROFILE="$APP_PATH/embedded.mobileprovision"
if [[ -f "$PROFILE" ]]; then
  EXPIRATION="$(
    security cms -D -i "$PROFILE" 2>/dev/null \
      | plutil -extract ExpirationDate raw -o - - 2>/dev/null || true
  )"
  if [[ -n "$EXPIRATION" ]]; then
    echo "Provisioning profile expires: $EXPIRATION"
  fi
fi
