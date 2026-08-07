# Guideline 5.6 被拒后的回复草稿

> 背景：2.1.0 (6) 于 2026-08-06 提交，2026-08-07 以 **Guideline 5.6 –
> Developer Code of Conduct** 被拒，理由是「App 包含在审核过程中似乎被刻意隐藏的功能」。
>
> 排查结论见本文末尾。回复前 **必须先完成第一节的准备工作**，
> 否则等于再向 Apple 陈述一次不实信息。

---

## 一、发送前必须完成（顺序不能反）

- [ ] Windows 被控端已就绪并长期开机联网
- [ ] 设置**永久密码**（审核可能跨多天、多次尝试）
- [ ] 开启无人值守 / 自动接受连接
- [ ] 从 iOS 端**实测连接成功**，能看到画面并能操作
- [ ] 记录真实的设备 ID、密码、Windows 版本、屏幕分辨率、
      以及客户端里显示的 **hostname**（务必与下方回复中的表述一致）
- [ ] 关闭那台 Android 模拟器（`RDeskDemo` AVD），审核期间不要再让它在线
- [ ] 用真实值替换下方所有 `<...>` 占位符

> **hostname 一致性是本次被拒的直接原因**，务必核对。
> 客户端会把服务端返回的 hostname 显示在会话页标题
> （[router.dart:163](../flutter_client/lib/src/utils/router.dart:163)），
> 审核员看到的名字必须和你在备注里描述的设备对得上。
>
> 核对命令（密码换成新的永久密码）：
>
> ```bash
> H=$(printf '<新密码>' | shasum -a 256 | awk '{print $1}')
> curl -s -X POST "https://qisw.top/api/preview/resolve/<新设备ID>" \
>   -H 'Content-Type: application/json' \
>   -d "{\"password_hash\":\"$H\",\"requester_id\":\"precheck\"}"
> ```
>
> 返回里的 `hostname` 和 `platform` 就是审核员会看到的值。

---

## 二、回复 App 审核（英文，直接粘贴）

> 位置：App Store Connect → App 审核 → 该提交 → 「回复 App 审核」

```
Thank you for the review and for flagging this.

We have identified what caused this, and we want to be straightforward about it.

WHAT WAS WRONG

Our App Review notes described the demo host device as "an Android phone."
That description was inaccurate. The device we made available was an Android
emulator (system image "sdk_gphone64_arm64") running on our development
machine. We had chosen an emulator so that the reviewer would not see any
personal data, but we failed to say so in the notes, and the notes instead
described it as a physical phone.

We understand this was our error and we apologize. The device the reviewer
connected to reported itself as "sdk_gphone64_arm64," which did not match what
our notes said. We can see how that discrepancy looked, and we also recognize
that pointing a reviewer at a virtual machine was the wrong choice for a remote
desktop client under Guideline 4.2.7. This was a mistake in how we prepared the
review environment, not an attempt to conceal anything from App Review.

THE APP ITSELF CONTAINS NO HIDDEN FEATURES

To be specific about what the binary does and does not contain:

- There is no embedded web browser or web view, and no component that loads
  remote HTML or scripts.
- There is no remote configuration, feature flag, or server response that
  enables, unlocks, or changes any part of the user interface.
- There is no hidden entry point of any kind: no debug menu, no tap-count or
  long-press unlock, no build that behaves differently for particular users,
  accounts, regions, or dates.
- There is no dynamic code loading (no dlopen/dlsym, no JavaScript engine, no
  downloaded executable code).
- The app declares no custom URL schemes and no background modes.
- Every screen reachable in the app is reachable from the tab bar on first
  launch, with no preconditions.

All functionality visible to the reviewer is the functionality described on our
product page: connecting to a remote host that the user owns, viewing its
screen, sending input, transferring files, and syncing clipboard text.

ABOUT GUIDELINE 4.2.7

RDesk is a remote desktop client only. It does not provide, host, resell, or
broker any virtual machine, cloud desktop, or remote computer. Users connect
only to devices they own or are explicitly authorized to access, by entering
that device's ID and a password that the device's owner sets. We do not host
any content ourselves, and we do not provide an app store, code execution, or
software distribution on the host side.

NEW DEMO ENVIRONMENT

We have replaced the test environment with a physical Windows computer that we
own, which will remain powered on and online for the duration of the review:

  Host type:    Physical Windows PC (<Windows 版本，例如 Windows 11 Pro 23H2>)
  Host name shown in the app: <客户端显示的 hostname>
  Screen resolution: <分辨率>
  Device ID:    <设备 ID>
  Password:     <永久密码>

Steps to connect (verified by us on a physical iPhone before this reply):
1. Open the app and tap "远程连接" (Remote Connection) in the bottom tab bar.
2. Enter the Device ID above in the "设备代码" (Device Code) field.
3. Enter the Password above in the "验证码" (Access Code) field.
4. Leave the mode set to "远程控制" (Remote Control), which is the default.
5. Tap the blue "密码连接" (Connect with Password) button.
6. The remote Windows desktop appears. You can move the cursor, click, type,
   and use the toolbar controls at the top of the screen.

The Android emulator referenced in our previous notes has been shut down and is
no longer reachable.

IF SOMETHING ELSE WAS MEANT

If your finding refers to something other than the mismatch described above, we
would be grateful if you could point us to the specific feature or screen. We
will address it directly and completely. We want this resolved correctly rather
than resubmitted on a guess.

Thank you for your time.
```

---

## 三、替换后的 App 审核备注（英文，覆盖原备注）

> 原备注是中文且包含「该演示设备为 Android 手机」这句错误表述，**必须整段替换**。
> 改用英文是为了让审核员无歧义地读到设备信息。

```
TEST ENVIRONMENT

RDesk is a remote desktop client. Demonstrating it requires a second device to
connect to. We keep a physical Windows computer that we own powered on and
online for the duration of the review:

  Host type:    Physical Windows PC (<Windows 版本>)
  Host name:    <客户端显示的 hostname>
  Resolution:   <分辨率>
  Device ID:    <设备 ID>
  Password:     <永久密码>

Unattended access is enabled, so no manual approval is needed on the host side.

To connect:
1. Open the app, tap "远程连接" (Remote Connection) in the bottom tab bar.
2. Enter the Device ID in "设备代码" (Device Code).
3. Enter the Password in "验证码" (Access Code).
4. Keep the mode as "远程控制" (Remote Control) — this is the default.
5. Tap the blue "密码连接" (Connect with Password) button.
6. The remote desktop appears. Click, type, and use the top toolbar to control
   the host.

If the app reports that no online device was found, the host is temporarily
offline. Please contact us at 641742030@qq.com and we will restore it
immediately.

GUIDELINE 4.2.7 — REMOTE DESKTOP CLIENT

- The app connects only to devices the user owns or is explicitly authorized to
  access. It does not provide, host, or resell any virtual machine, cloud
  desktop, or remote computer.
- All displayed content originates from the user's own host device. We host no
  content ourselves.
- The host side offers no third-party app store and does not download or
  execute external code.

NO HIDDEN OR REMOTELY ENABLED FUNCTIONALITY

- No embedded web browser or web view; nothing loads remote HTML or scripts.
- No remote configuration or feature flags. No server response enables,
  unlocks, or alters any part of the UI.
- No debug menu, no tap-count or long-press unlock, no behavior that varies by
  user, account, region, or date.
- No dynamic code loading. No custom URL schemes. No background modes.
- Every screen is reachable from the tab bar on first launch.

CONNECTION SECURITY

- The host must actively start sharing and set a password. The client must
  supply the correct password to connect.
- All traffic between the app and our server (sign-in, screen data, input
  events) travels over HTTPS / WSS.
- When relayed through our server, screen data is readable on the server. This
  app does not implement end-to-end encryption, and our privacy policy states
  this limitation explicitly.
- On the same local network, a direct address can be used, in which case data
  does not pass through our server.
- The user can end the session from the host at any time.

APP TRANSPORT SECURITY

Info.plist sets NSAllowsArbitraryLoads. The default server is https://qisw.top
and normal use is HTTPS. However, the app lets users enter their own
self-hosted relay/signaling server address, and also supports connecting
directly to LAN IP addresses such as 192.168.x.x. These are entered by the user
at runtime, cannot be enumerated in advance as domain exceptions, and LAN
devices usually have no trusted certificate.

SCREEN RECORDING PERMISSION

When iOS acts as the host, the app uses a ReplayKit Broadcast Extension to
capture the screen. Capture starts only when the user manually selects RDesk in
the system screen-recording menu. The app cannot begin capture without the
user's knowledge.

Note that due to iOS platform limits, an iOS host can only share its screen and
cannot accept remote touch input. Remote control applies to Windows, macOS, and
Android hosts only. The "iOS 被控" (iOS Host) screen states this limit to users.

PHOTO LIBRARY PERMISSION

Info.plist declares NSPhotoLibraryUsageDescription. It is used by the file
transfer feature so users can pick a local image to send to a remote device.
The prompt is triggered by the file picker only after the user taps "文件传输"
(File Transfer). The app never reads the photo library in the background.
```

---

## 四、排查记录

Apple 的 5.6 措辞是模板，不指明具体功能。以下是我们自己的排查结果。

### 客户端不含隐藏功能（已逐项核对）

| 检查项 | 结果 | 依据 |
|---|---|---|
| WebView / 内嵌浏览器 | 无 | Dart、Swift、ObjC 全量搜索无 `WKWebView` / `webview` |
| 远程加载内容 | 无 | 无 `url_launcher`、无 `loadUrl` |
| 远程功能开关 | 无 | 无 `featureFlag` / `remoteConfig` / 服务端驱动的 UI 分支 |
| 隐藏入口 | 无 | 无连点解锁、无 `kDebugMode` 门控界面 |
| 动态代码加载 | 无 | 无 `dlopen` / `dlsym` / JS 引擎 |
| URL scheme / 后台模式 | 无 | `Runner/Info.plist` 未声明 |
| iOS 原生代码量 | 4 个文件 | `AppDelegate` / `SceneDelegate` / `FrameShared` / `SampleHandler` |

### 真正的问题：备注与实际环境不符

审核备注称演示设备为「Android 手机」，实际是 Android 模拟器，且模拟器如实
向服务端和客户端上报了自己的身份：

```
hostname                    sdk_gphone64_arm64
ro.product.model            sdk_gphone64_arm64
ro.build.characteristics    emulator
ro.kernel.qemu              1
```

客户端会把 hostname 显示在会话页标题，因此审核员看到的名字与备注描述矛盾。
同时，让审核员连接一台虚拟机本身就与 Guideline 4.2.7 冲突——
而我们的备注里恰好写着「不提供任何云端主机或虚拟机服务」。

> **教训**：审核备注里对演示环境的每一句描述，都必须与审核员实际看到的
> 标识符（hostname、平台、分辨率）逐项核对。
> 用 `scripts/check_review_host.sh` 可以拿到服务端返回的真实 `hostname` 与 `platform`。
