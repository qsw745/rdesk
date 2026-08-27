# RDesk macOS 分发指南（Developer ID 自行分发）

本文档覆盖 macOS 版通过 **Developer ID 签名 + Apple 公证**在 Mac App Store 之外
分发的完整流程。这条路线与 iOS 上架（见 [app-store-submission.md](app-store-submission.md)）
互相独立。

## 为什么不走 Mac App Store

远程桌面需要屏幕录制、辅助功能（控制鼠标键盘）等权限，这些在 App Sandbox 下
受限严重。`macos/Runner/Release.entitlements` 中**刻意未启用**
`com.apple.security.app-sandbox`，因此只能走 Developer ID 分发。

## 前置条件

| 项目 | 当前状态 |
|---|---|
| Developer ID Application 证书 | 已具备：`qi shiwei (6N5T3G6H33)` |
| Hardened Runtime | 签名时通过 `--options runtime` 启用 |
| 公证凭据 | **尚未配置**，见下方「一次性配置」 |

## 一、构建

本机开发安装优先使用项目脚本：

```bash
cd flutter_client && ./build_install.sh macos
```

该脚本会完成 release 构建、Developer ID 重签名、签名校验、备份并替换
`/Applications/rdesk.app`，最后重新启动应用。保持同一个 Developer ID 与
TeamIdentifier 很重要；若直接安装 Flutter 的 adhoc 签名产物，每次构建的代码身份
都可能变化，macOS 会把已有的屏幕录制/辅助功能授权视为属于旧应用，从而再次提示权限。

仅需要生成原始构建产物时可执行：

```bash
cd flutter_client && flutter build macos --release
```

产物：`build/macos/Build/Products/Release/rdesk.app`

Flutter 默认产出的是 **adhoc 签名**（`TeamIdentifier=not set`），必须重新签名。

## 二、签名

签名必须**从内到外**：先签所有内嵌 framework/dylib，最后签主 App。
顺序颠倒会导致外层签名失效。

```bash
APP=flutter_client/build/macos/Build/Products/Release/rdesk.app
ID="Developer ID Application: qi shiwei (6N5T3G6H33)"
ENT=flutter_client/macos/Runner/Release.entitlements

for f in "$APP/Contents/Frameworks/"*; do
  codesign --force --sign "$ID" --options runtime --timestamp "$f"
done

codesign --force --sign "$ID" --options runtime --timestamp --entitlements "$ENT" "$APP"
```

`--options runtime`（Hardened Runtime）和 `--timestamp`（安全时间戳）都是
公证的**硬性要求**，缺任一项公证必被拒。

### 验证签名

项目提供了与本地安装脚本相同的校验入口：

```bash
bash scripts/verify_macos_install.sh /Applications/rdesk.app
```

```bash
codesign --verify --deep --strict --verbose=2 "$APP"
```

期望输出包含 `valid on disk` 与 `satisfies its Designated Requirement`。

```bash
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|flags"
```

期望看到 `flags=0x10000(runtime)`、`Developer ID Application`、`TeamIdentifier=6N5T3G6H33`。

## 三、公证

### 一次性配置凭据

需要 **app-specific password**（不是 Apple ID 登录密码）：
到 https://account.apple.com → 登录 → “App 专用密码” → 生成一个。

```bash
xcrun notarytool store-credentials "rdesk" --apple-id "你的AppleID" --team-id 6N5T3G6H33
```

命令会交互式提示输入 app-specific password，存入钥匙串，后续复用。

### 提交公证

```bash
cd flutter_client/build/macos/Build/Products/Release
ditto -c -k --keepParent rdesk.app rdesk.zip
xcrun notarytool submit rdesk.zip --keychain-profile "rdesk" --wait
```

`--wait` 会阻塞直到 Apple 返回结果，通常几分钟。

若返回 `Invalid`，用返回的 submission id 查看具体原因：

```bash
xcrun notarytool log <submission-id> --keychain-profile "rdesk"
```

### 装订票据

公证通过后必须 staple，否则用户首次打开在离线环境下仍会被拦截：

```bash
xcrun stapler staple rdesk.app
xcrun stapler validate rdesk.app
```

## 四、验证最终结果

```bash
spctl -a -vvv -t install rdesk.app
```

公证并 staple 后应显示 `source=Notarized Developer ID`。
若显示 `Unnotarized Developer ID`，说明公证或 staple 未生效。

> 注意：若本机执行过 `spctl --master-disable`，评估结果会带
> `override=security disabled`，此时结果不能代表普通用户的机器。
> 建议在一台未改过 Gatekeeper 设置的机器上做最终验证。

## 五、打包分发

在 `.app` 公证并 staple **之后**再打 DMG。DMG 本身需要独立走一遍
**签名 → 公证 → staple**，顺序不能变：

```bash
hdiutil create -volname "RDesk" -srcfolder rdesk.app -ov -format UDZO rdesk.dmg
codesign --force --sign "Developer ID Application: qi shiwei (6N5T3G6H33)" --timestamp rdesk.dmg
xcrun notarytool submit rdesk.dmg --keychain-profile "rdesk" --wait
xcrun stapler staple rdesk.dmg
```

> **踩过的坑**：跳过 `codesign` 直接公证 DMG，`stapler validate` 会通过，
> 但 `spctl` 报 `source=no usable signature` —— 公证票据不能替代签名。
> 且签名会使已装订的票据失效，必须严格按「签名 → 公证 → staple」执行。

### 验证 DMG

DMG 要用 `open` 类型评估，不是 `install`（后者是给 `.app` 用的）：

```bash
spctl -a -t open --context context:primary-signature -vv rdesk.dmg
```

## 六、发布到下载页

站点：**https://qisw.top/rdesk/download**

| 内容 | 服务器路径 |
|---|---|
| 下载页 | `/data/website/rdesk/download.html` |
| 安装包 | `/data/website/rdesk/dl/RDesk-<版本>.dmg` / `.apk` |
| 图标 | `/data/website/rdesk/icon.png` |
| nginx 配置 | `/opt/nginx/conf.d/site.conf`，80 与 443 两个 server 各一组 location |

更新安装包的流程：

```bash
# 1. 上传新包（文件名带版本号，便于回滚）
scp rdesk.dmg 101.37.21.147:/data/website/rdesk/dl/RDesk-2.1.1.dmg

# 2. 算哈希，更新 download.html 中的版本号、体积与 SHA-256
shasum -a 256 rdesk.dmg

# 3. 上传页面
scp deploy/download.html 101.37.21.147:/data/website/rdesk/download.html
```

nginx 无需 reload（静态文件直接生效），仅新增 location 时才需要。

> **发布后务必完整下载一次并核对哈希**，只看 HTTP 200 不足以说明文件完整——
> 传输截断同样会返回 200。DMG 还应再验证 `xcrun stapler validate`，
> 确认公证票据在传输后仍然有效。

### Android 包的签名

APK 使用发布密钥签名（`CN=RDesk, O=QSW`），配置在 `flutter_client/android/key.properties`。
该文件**不得提交到版本库**；密钥丢失将无法为已安装用户推送更新。

## 首次运行所需的系统权限

macOS 版作为被控端时，用户需在「系统设置 → 隐私与安全性」中手动授予：

- **屏幕录制** — 采集屏幕画面
- **辅助功能** — 注入鼠标、键盘事件

这两项无法通过 Info.plist 预声明，只能由用户在系统弹窗或设置中授权。
分发时应在说明中提示用户，否则会被误认为“功能不可用”。
