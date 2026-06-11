#!/bin/bash
# RDesk 打包安装脚本
# 用法:
#   ./build_install.sh          # 打包并安装 macOS + iOS
#   ./build_install.sh macos    # 仅 macOS
#   ./build_install.sh ios      # 仅 iOS

set -e
cd "$(dirname "$0")"

IPHONE_DEVICE_ID="00008120-001C29311438C01E"

build_macos() {
  echo "━━━ 构建 macOS (release) ━━━"
  flutter build macos --release
  echo "━━━ 安装 macOS ━━━"
  flutter install --device-id macos
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
