# Guideline 5.6 被拒后的回复草稿

> 背景：2.1.0 (6) 于 2026-08-06 提交，2026-08-07 以 **Guideline 5.6 –
> Developer Code of Conduct** 被拒，理由是「App 包含在审核过程中似乎被刻意隐藏的功能」。
>
> 排查结论见本文末尾。回复前 **必须先完成第一节的准备工作**，
> 否则等于再向 Apple 陈述一次不实信息。

---

## 一、发送前必须完成（顺序不能反）

- [x] 关闭 Android 模拟器（`RDeskDemo` AVD）——已关闭，服务端返回 `found:false`，
      旧密码 `Review2026` 作废
- [x] 改用**真实物理设备**：一加手机（型号 `PLU110`，Android 16，OxygenOS 16.0.8.300）
- [x] 在该手机上新建独立用户（id 10），**只在该用户下安装 RDesk**，
      主用户（机主）已移除该 App，审核员接触不到机主的任何数据
- [x] 设置永久密码、开启无人值守 / 自动接受连接
- [x] 授权录屏（`ScreenCaptureService` 前台运行，`types=0x00000020`）与无障碍
      （`accessibility_enabled=1`）
- [x] 加入电池优化白名单（`cmd deviceidle whitelist +com.qsw.rdesk`）
- [ ] `./scripts/check_review_host.sh` 全绿，退出码 0
      —— 2026-08-13 重装 APK（versionCode 11）并重新授权录屏后**尚未重跑**，
      之前那次结论已过期。发回复前必须再跑一次：
      `RDESK_REVIEW_DEVICE_ID=660725198 RDESK_REVIEW_PASSWORD='<密码>' ./scripts/check_review_host.sh`
- [x] 从**真机 iPhone** 实测连接一次 —— 2026-08-13 用 iPhone 17 Pro Max 装
      build 11 连 `660725198` 实测通过：画面、返回/主页/任务、长按、仅观看、
      指针模式、画面旋转均由操作者在屏幕上确认可用；被控端日志侧确认整段会话
      无崩溃、无 `STOP_REASON`、投屏未中断。
      注：单个手势是否逐一到达无法从日志证实（Android 不记录无障碍手势注入），
      该结论来自操作者观察。
- [x] **移除「隐私屏」与「录屏」两个空开关**（见第四节「界面上的空开关」）——
      已于 `0b0ecc9` 从移动端「操作」面板、桌面端侧栏、旧 `RemoteToolbar` 三处
      及 `SessionProvider` 中删除，并出 **build 11**。
      **提交时必须选 build 11**：build 10 仍含这两个开关，而第三节备注声明
      「界面上的每个控件都如其标签所述」。
- [x] 用真实值替换下方所有 `<...>` 占位符

**实测得到的真实值（下方文案已按此填写）：**

| 项 | 值 |
|---|---|
| hostname（审核员看到的） | `PLU110` |
| platform | `android` |
| 设备 ID | `660725198` |
| 密码 | `<见 ASC 审核备注>` |

> ⚠️ **本仓库是公开的，演示机密码一律不得写入文档。**
> 该被控端为真实手机且开启了无人值守 + 无障碍服务，拿到设备 ID 与密码
> 即可完整操控它。真实密码只存在于 App Store Connect 的审核备注中。
> 本地验证时用环境变量传入，不要落盘：
>
> ```bash
> RDESK_REVIEW_DEVICE_ID=660725198 RDESK_REVIEW_PASSWORD='<密码>' \
>   ./scripts/check_review_host.sh
> ```
>
> 审核通过后请立即删除该 Android 用户或更换密码。
| 分辨率 | 661×1440 |

> **hostname 一致性是本次被拒的直接原因**，务必核对。
> 客户端会把服务端返回的 hostname 显示在会话页标题
> （[router.dart:163](../flutter_client/lib/src/utils/router.dart:163)），
> 审核员看到的名字必须和备注里描述的设备对得上。
>
> 随时可重新核对：
>
> ```bash
> RDESK_REVIEW_DEVICE_ID=660725198 RDESK_REVIEW_PASSWORD='<密码>' \
>   ./scripts/check_review_host.sh
> ```
>
> 脚本会打印 `hostname` 与 `platform`，并在检出模拟器标识时直接判失败。

> ⚠️ **审核期间这台手机必须一直停在用户 10（qsw）**。安卓的机制是切回主用户
> 就会把该用户的应用停掉，被控端一停审核员就连不上，又是 Guideline 2.1。
> 重启后手机默认进主用户，需要手动切回去。

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

We have replaced the emulator with a physical Android phone that we own, and it
will remain powered on, charging, and online for the duration of the review:

  Host type:    Physical Android phone, OnePlus, model PLU110, Android 16
  Host name shown in the app: PLU110
  Screen resolution: 661 x 1440
  Device ID:    660725198
  Password:     <填入真实密码后再发送>

The host name the app displays for this device is "PLU110," which is the actual
model identifier reported by the hardware. It matches the device described here.

So that the reviewer sees no personal data, we created a separate Android user
profile on that phone and installed RDesk only in that profile. The phone's
primary profile does not have the app installed and is not reachable from it.
We are stating this explicitly so that the empty home screen is not mistaken for
anything being concealed: the profile is genuinely new, not a hidden or altered
view of a device in use.

Steps to connect (verified by us on a physical iPhone before this reply):
1. Open the app and tap "远程连接" (Remote Connection) in the bottom tab bar.
2. Enter the Device ID above in the "设备代码" (Device Code) field.
3. Enter the Password above in the "验证码" (Access Code) field.
4. Leave the mode set to "远程控制" (Remote Control), which is the default.
5. Tap the blue "密码连接" (Connect with Password) button.
6. The remote Android screen appears. A single tap sends a tap, a long press
   sends a long press, and a two-finger pinch zooms the view. The toolbar at the
   top provides Back, Home, and Recents, which operate the host's system UI.

Unattended access is enabled, so no manual approval is needed on the host side.

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
connect to. We keep a physical Android phone that we own powered on, charging,
and online for the duration of the review:

  Host type:    Physical Android phone, OnePlus, model PLU110, Android 16
  Host name:    PLU110
  Resolution:   661 x 1440
  Device ID:    660725198
  Password:     <填入真实密码后再发送>

The host name shown in the app for this device is "PLU110," the model
identifier reported by the hardware, matching the device described above.

To keep personal data out of the review environment, RDesk is installed in a
separate Android user profile on that phone, which contains no personal
accounts or data. The empty home screen reflects a genuinely new profile.

Unattended access is enabled, so no manual approval is needed on the host side.

Build under review: 2.1.0 (11)

To connect:
1. Open the app, tap "远程连接" (Remote Connection) in the bottom tab bar.
2. Enter the Device ID in "设备代码" (Device Code).
3. Enter the Password in "验证码" (Access Code).
4. Keep the mode as "远程控制" (Remote Control) — this is the default.
5. Tap the blue "密码连接" (Connect with Password) button.
6. The remote Android screen appears.

If the app reports that no online device was found, the host is temporarily
offline. Please contact us at 641742030@qq.com and we will restore it
immediately.

GESTURES ON THE REMOTE SCREEN

  Single tap           sends a tap at that point on the host
  Long press           sends a long press at that point on the host
  Drag                 sends the same swipe on the host (scrolling)
  Two-finger pinch     zooms the local view only; the host is not affected

COMPLETE LIST OF CONTROLS IN THE SESSION SCREEN

We list every control exhaustively. There are no other menus, gestures, or
entry points in this screen.

A bottom bar with five items:

  返回 (Back)          host system Back
  主页 (Home)          host system Home
  任务 (Recents)       host system Recents
  键盘 (Keyboard)      opens a text box; the text is typed into whichever input
                       field currently has focus on the host
  操作 (Actions)       opens the sheet described below

Tapping 操作 opens a sheet containing the remaining controls:

  Toggle row
    退出远控 (Disconnect)      ends the session and returns to the device list
    仅观看 (View only)         client-side switch; while it is on the app sends
                               no input of any kind to the host
    指针模式 (Pointer mode)    draws a pointer on the local view; dragging moves
                               the pointer, and three buttons send tap, long
                               press, or drag at the pointer's position. Added
                               because a finger cannot hit small targets on a
                               phone-sized remote screen.
    旋转画面 (Rotate view)     rotates the local view by 90 degrees per tap, for
                               viewing a landscape host on a portrait phone. The
                               host's own screen orientation is not changed.
    全屏 (Full screen)         hides the iOS status and home indicator locally
    隐藏工具栏 (Hide bar)      hides the bottom bar; a button appears at the top
                               right to bring it back

  操作 (Actions) group
    滚动 上滑 / 下滑           sends a swipe up or down on the host
    删除 (Delete)              deletes one character in the focused host input
    回车 (Enter)               sends Enter to the focused host input
    唤醒屏幕 (Wake screen)     wakes the host's display

  剪贴板 (Clipboard) group
    发送到远端                 sends this device's clipboard text to the host
    从远端获取                 fetches the host's clipboard text to this device

  更多 (More) group
    画质设置 (Quality)         requests a JPEG quality and frame rate
    显示器 (Displays)          switches monitor when the host has more than one
    文件传输 (File transfer)   opens the file transfer screen
    会话聊天 (Chat)            opens the in-session chat screen

仅观看, 指针模式, 旋转画面, 全屏, and 隐藏工具栏 change only what this device
displays or sends; they do not reach the host. Every other control results in a
request to the host. Every control does what its label says — the app contains
no switch that reports success without acting.

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
- Every control in the session screen is enumerated above, including the ones
  that only affect local display.

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
cannot accept remote touch input. Remote control applies to macOS and Android
hosts only. The "iOS 被控" (iOS Host) screen states this limit to users.

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

### 界面上的空开关（2026-08-12 发现，发回复前必须处理）

上面那张表查的是「有没有藏起来的功能」，漏了反过来的一种：**界面上有、但什么都
不做的开关**。会话页「操作」面板里有两个：

| 开关 | 实际行为 | 依据 |
|---|---|---|
| 隐私屏 | 发送 `privacy_on` / `privacy_off`，两种被控端都没有对应分支，恒返回 `false` | `RdeskAccessibilityService.performAction` 与 `DesktopHostService.performRemoteAction` 的 switch 里都没有该 case |
| 录屏 | 只翻转一个 bool。`_recordedFrames` 除声明、getter、`clear()` 外从未被写入 | `session_provider.dart` 全文搜索 `_recordedFrames` |

两者点击后都会弹出「隐私屏已开启」「录屏已开始」的提示——**App 明确告知用户一件
没有发生的事**。这正是 5.6 措辞里 manipulative and misleading behavior 所指的
行为，比「隐藏功能」更直接。

处理方式二选一，不能都不做：

1. **移除这两个开关**（推荐）。改动只在 `remote_control_panel.dart` 的开关行与
   `session_provider.dart` 的两个 toggle 方法，成本很低。
2. 真正实现它们。隐私屏需要被控端加协议与遮罩窗口，录屏需要观看端落盘编码，
   工作量都不小，且在审核期间新增功能会带来新的审核面。

> **处理结果**：已按方案 1 执行（`0b0ecc9`），并出 build 11。
> build 10 仍含这两个开关，提交时不要选它。

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
