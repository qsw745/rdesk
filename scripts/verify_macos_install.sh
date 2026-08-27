#!/bin/bash

set -euo pipefail

APP_PATH="${1:-/Applications/rdesk.app}"
EXPECTED_TEAM_ID="${RDESK_MAC_TEAM_ID:-6N5T3G6H33}"
EXPECTED_IDENTITY="${RDESK_MAC_SIGN_IDENTITY:-Developer ID Application: qi shiwei (6N5T3G6H33)}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到 macOS 应用：$APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"

if ! grep -Fq "Authority=$EXPECTED_IDENTITY" <<<"$SIGNATURE_INFO"; then
  echo "macOS 应用不是使用预期 Developer ID 签名：$EXPECTED_IDENTITY" >&2
  exit 1
fi

if ! grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$SIGNATURE_INFO"; then
  echo "macOS 应用 TeamIdentifier 不正确：期望 $EXPECTED_TEAM_ID" >&2
  exit 1
fi

if ! grep -Fq "flags=0x10000(runtime)" <<<"$SIGNATURE_INFO"; then
  echo "macOS 应用未启用 Hardened Runtime" >&2
  exit 1
fi

echo "macOS 安装签名验证通过：$APP_PATH"
