#!/bin/bash
# Build, sign, notarize and staple RDesk for one architecture into dist/.
#
#   scripts/release_macos.sh arm64    -> dist/RDesk-<ver>-macos-arm64.dmg
#   scripts/release_macos.sh x86_64   -> dist/RDesk-<ver>-macos-x64.zip
#
# Needs the Developer ID certificate in the login keychain and a notarytool
# keychain profile (default "rdesk", see docs/macos-distribution.md).
set -euo pipefail

ARCH="${1:?usage: release_macos.sh arm64|x86_64}"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo "unknown arch $ARCH" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/flutter_client"
IDENTITY="${RDESK_MAC_SIGN_IDENTITY:-Developer ID Application: qi shiwei (6N5T3G6H33)}"
PROFILE="${RDESK_NOTARY_PROFILE:-rdesk}"
VERSION="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' "$CLIENT/pubspec.yaml")"
DERIVED="$CLIENT/build/macos-release-$ARCH"
APP="$DERIVED/Build/Products/Release/rdesk.app"
OUT="$ROOT/dist"
WORK="$(mktemp -d /private/tmp/rdesk-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

notarize() {
  local file="$1" result status id
  result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json)"
  status="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$result")"
  id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$result")"
  echo "公证 $(basename "$file")：$status ($id)"
  if [[ "$status" != Accepted ]]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    exit 1
  fi
}

echo "━━━ 构建 RDesk $VERSION ($ARCH) ━━━"
cd "$CLIENT"
flutter build macos --release --config-only
rm -rf "$DERIVED"
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath "$DERIVED" -jobs 4 \
  ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO build >"$WORK/xcodebuild.log" 2>&1 || {
    tail -40 "$WORK/xcodebuild.log" >&2; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/rdesk")" == "$ARCH" ]] || {
  echo "主程序架构不是 $ARCH" >&2; exit 1; }

echo "━━━ 内嵌开机助手并签名 ━━━"
bash "$ROOT/scripts/bundle_macos_wake_helper.sh" "$APP" "$IDENTITY"
for item in "$APP/Contents/Frameworks/"*; do
  [[ -e "$item" ]] && codesign --force --sign "$IDENTITY" --options runtime --timestamp "$item"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$CLIENT/macos/Runner/Release.entitlements" "$APP"
bash "$ROOT/scripts/verify_macos_install.sh" "$APP"

echo "━━━ 公证应用 ━━━"
ditto -c -k --keepParent "$APP" "$WORK/rdesk.zip"
notarize "$WORK/rdesk.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv -t install "$APP"

if [[ "$ARCH" == arm64 ]]; then
  DMG="$OUT/RDesk-$VERSION-macos-arm64.dmg"
  echo "━━━ 制作并公证 DMG ━━━"
  mkdir "$WORK/dmg"
  ditto "$APP" "$WORK/dmg/rdesk.app"
  ln -s /Applications "$WORK/dmg/Applications"
  rm -f "$DMG"
  hdiutil create -volname "随控" -srcfolder "$WORK/dmg" -ov -format UDZO "$DMG" >/dev/null
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
  echo "完成：$DMG"
else
  ZIP="$OUT/RDesk-$VERSION-macos-x64.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "完成：$ZIP"
fi
