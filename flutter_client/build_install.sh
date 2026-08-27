#!/bin/bash
# RDesk 打包安装脚本
# 用法:
#   ./build_install.sh          # 打包并安装 macOS + iOS
#   ./build_install.sh macos    # 仅 macOS
#   ./build_install.sh ios      # 仅 iOS

set -e
cd "$(dirname "$0")"

IPHONE_DEVICE_ID="00008120-001C29311438C01E"
MAC_APP_PATH="$PWD/build/macos/Build/Products/Release/rdesk.app"
MAC_INSTALL_PATH="${RDESK_MAC_INSTALL_PATH:-/Applications/rdesk.app}"
MAC_SIGN_IDENTITY="${RDESK_MAC_SIGN_IDENTITY:-Developer ID Application: qi shiwei (6N5T3G6H33)}"
MAC_ENTITLEMENTS="$PWD/macos/Runner/Release.entitlements"
MAC_VERIFY_SCRIPT="$PWD/../scripts/verify_macos_install.sh"

sign_macos_app() {
  if ! security find-identity -v -p codesigning | grep -Fq "$MAC_SIGN_IDENTITY"; then
    echo "❌ 未找到 macOS 签名证书：$MAC_SIGN_IDENTITY" >&2
    exit 1
  fi

  echo "━━━ 使用 Developer ID 签名 macOS 应用 ━━━"
  for embedded_item in "$MAC_APP_PATH/Contents/Frameworks/"*; do
    if [[ -e "$embedded_item" ]]; then
      codesign --force --sign "$MAC_SIGN_IDENTITY" \
        --options runtime --timestamp "$embedded_item"
    fi
  done

  codesign --force --sign "$MAC_SIGN_IDENTITY" \
    --options runtime --timestamp \
    --entitlements "$MAC_ENTITLEMENTS" \
    "$MAC_APP_PATH"

  bash "$MAC_VERIFY_SCRIPT" "$MAC_APP_PATH"
}

install_macos_app() {
  local backup_root
  local backup_app
  local install_completed=0

  backup_root="$(mktemp -d /private/tmp/rdesk-macos-install.XXXXXX)"
  backup_app="$backup_root/rdesk.app"

  restore_previous_install() {
    local status=$?
    if [[ $status -ne 0 && $install_completed -eq 0 && \
          -d "$backup_app" && ! -e "$MAC_INSTALL_PATH" ]]; then
      mv "$backup_app" "$MAC_INSTALL_PATH"
      echo "⚠️ 安装失败，已恢复旧版 RDesk" >&2
    fi
    return $status
  }
  trap restore_previous_install EXIT

  if pgrep -x rdesk >/dev/null 2>&1; then
    pkill -x rdesk
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ! pgrep -x rdesk >/dev/null 2>&1; then
        break
      fi
      sleep 0.2
    done
  fi

  if [[ -d "$MAC_INSTALL_PATH" ]]; then
    mv "$MAC_INSTALL_PATH" "$backup_app"
  fi

  ditto "$MAC_APP_PATH" "$MAC_INSTALL_PATH"
  bash "$MAC_VERIFY_SCRIPT" "$MAC_INSTALL_PATH"
  install_completed=1
  trap - EXIT

  echo "旧版备份：$backup_app"
  open "$MAC_INSTALL_PATH"
}

build_macos() {
  echo "━━━ 构建 macOS (release) ━━━"
  flutter build macos --release
  sign_macos_app
  echo "━━━ 安装 macOS ━━━"
  install_macos_app
  echo "✅ macOS 安装完成"
}

build_ios() {
  echo "━━━ 构建 iOS (release, 自动签名) ━━━"
  # 先让 flutter 生成 release 产物
  flutter build ios --release --no-codesign

  # 用 xcodebuild 编译 + 自动签名
  xcodebuild -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -destination "id=$IPHONE_DEVICE_ID" \
    -configuration Release \
    -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="Apple Development" \
    build

  # 获取构建产物路径
  BUILT_DIR=$(xcodebuild -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -showBuildSettings -configuration Release 2>/dev/null \
    | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

  echo "━━━ 安装 iOS ━━━"
  xcrun devicectl device install app \
    --device "$IPHONE_DEVICE_ID" \
    "$BUILT_DIR/Runner.app"

  echo "✅ iOS 安装完成"
}

case "${1:-all}" in
  macos)  build_macos ;;
  ios)    build_ios ;;
  all)    build_macos; build_ios ;;
  *)      echo "用法: $0 [macos|ios|all]"; exit 1 ;;
esac

echo ""
echo "🎉 全部完成！"
