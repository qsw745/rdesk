#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
IDENTITY="$2"
STAGING="$(mktemp -d /private/tmp/rdesk-wake-build.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
cd "$ROOT/tools/wake-helper"
for ARCH in arm64 amd64; do
  CGO_ENABLED=0 GOOS=darwin GOARCH="$ARCH" go build -trimpath -ldflags='-s -w' -o "$STAGING/$ARCH" .
done
mkdir -p "$APP/Contents/Helpers"
lipo -create "$STAGING/arm64" "$STAGING/amd64" -output "$APP/Contents/Helpers/rdesk-wake-helper"
chmod 755 "$APP/Contents/Helpers/rdesk-wake-helper"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/rdesk-wake-helper"
codesign --verify --strict "$APP/Contents/Helpers/rdesk-wake-helper"
