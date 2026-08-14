# Guideline 5.6 被拒后的回复草稿

> **两次被拒**，同一条 Guideline 5.6 – Developer Code of Conduct，Apple 两次发来
> 的是同一段模板文字（「App 包含在审核过程中似乎被刻意隐藏的功能」），不指明具体功能。
>
> | 时间 | 提交 | 结果 |
> |---|---|---|
> | 2026-08-06 | 2.1.0 (6) | 08-07 被拒（根因：备注把 Android 模拟器说成实体手机） |
> | 2026-08-13 | 2.1.0 (11) | 08-14 再次被拒，措辞相同 |
>
> **二拒复查结论**（见第四节，2026-08-14 修订）：
>
> 1. 备注**没有提供测试账号**，而云设备页与「我的-我的设备」挡在登录后，
>    审核员看不到这部分功能；备注却写着「没有随账号变化的行为」「每个界面
>    首次启动即可从标签栏到达，无前置条件」。这两句不成立。
> 2. build 11 的包里带着一整套**没有任何代码调用、界面上也没有入口**的相册库
>    与相册权限声明。App 有能力、界面无入口——这是对 5.6 措辞最贴合的解释，
>    也是唯一在二进制层面确证的问题。
>
> ⚠️ 复查过程中一度得出「备注还有三条声明与 build 11 不符」的结论，**其中两条
> 是错的**（详见第四节「一次错误的复查」）。教训见文末，比结论本身更值得记住。
>
> 本文第二、三节的文案已按 build 12 改写；在 build 12 上传、测试账号建好、
> 第一节全部核对完成之前，一个字都不要发出去。

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
- [x] `./scripts/check_review_host.sh` 全绿，退出码 0
      —— 2026-08-13 重装 APK（versionCode 11）、重新授权录屏、开启「保持屏幕常亮」后重跑通过。
      四段全绿，且服务端返回的身份与本文档声明逐字一致：
      `hostname=PLU110`、`platform=android`、画面 `661x1440`。
      注：多台设备在线时必须指定序列号，否则 adb 检查会给出假警报（见 `9edf981`）：
      `RDESK_REVIEW_DEVICE_ID=660725198 RDESK_REVIEW_PASSWORD='<密码>' RDESK_REVIEW_SERIAL=<序列号> ./scripts/check_review_host.sh`
- [x] 从**真机 iPhone** 实测连接一次 —— 2026-08-13 用 iPhone 17 Pro Max 装
      build 11 连 `660725198` 实测通过：画面、返回/主页/任务、长按、仅观看、
      指针模式、画面旋转均由操作者在屏幕上确认可用；被控端日志侧确认整段会话
      无崩溃、无 `STOP_REASON`、投屏未中断。
      注：单个手势是否逐一到达无法从日志证实（Android 不记录无障碍手势注入），
      该结论来自操作者观察。
- [x] **移除「隐私屏」与「录屏」两个空开关**（见第四节「界面上的空开关」）——
      已于 `0b0ecc9` 从移动端「操作」面板、桌面端侧栏、旧 `RemoteToolbar` 三处
      及 `SessionProvider` 中删除，并出 **build 11**。

### 二拒之后新增的阻塞项

- [x] **移除界面上够不到的相册能力**（2026-08-14）。这是二拒复查中唯一确证的
      二进制层面问题，也是目前对 5.6 措辞最贴合的解释：
      > build 11 的包里带着 `file_picker`、`DKImagePickerController`、
      > `DKPhotoGallery`、`SDWebImage`、`SwiftyGif` 五个 framework 和
      > `NSPhotoLibraryUsageDescription`，其中 `DKImagePickerController` 就是
      > 一整套相册选择界面。而 `lib/` 全量搜索**没有任何一行调用**它们，
      > 文件传输走的是自建的沙盒目录浏览器
      > （[file_manager_screen.dart](../flutter_client/lib/src/screens/file_manager_screen.dart)）。
      > 即：**App 具备访问相册的能力，界面上却没有任何入口**——这正是
      > 「features that appear to have been intentionally hidden」所描述的形态，
      > 且静态扫描很容易发现。
      处理（整套移除，而不是补声明）：
      - 删除 `ios/Runner/Info.plist` 的 `NSPhotoLibraryUsageDescription`
        （`plutil -lint` 通过）
      - 从 `pubspec.yaml` 移除 `file_picker: ^8.0.0`，连带移除 `cross_file`
      - 三端 `GeneratedPluginRegistrant` 自动摘掉 `FilePickerPlugin` 注册，
        两个 `Podfile.lock` 用 `pod install` 同步，`file_picker` 条目归零
      - `flutter analyze` 0 error 0 warning；`AndroidManifest.xml` 也无
        `READ_MEDIA_*` / `READ_EXTERNAL_STORAGE` 残留
      > 注：当初 build 4 被 **ITMS-90683** 退回（缺 `NSPhotoLibraryUsageDescription`）
      > 正是这套依赖引起的。依赖移除后二进制不再链接相册 API，不会再触发该错误。
      > 若 `pod install` 报 `String#unicode_normalize`，是本机 Ruby 的 locale 问题，
      > 加 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` 前缀即可。
- [x] **build 12 已打包**（2026-08-14，`flutter build ipa`，exit 0，21.9MB，
      比 build 11 的 23.1MB 小 1.2MB——正是那五个 framework 的体积）。产物实测：

      | 项 | 结果 |
      |---|---|
      | 主 App `CFBundleVersion` | 12 |
      | 扩展版本 | 12 / 2.1.0（已跟随主 App） |
      | `NSPhotoLibraryUsageDescription` | 无 |
      | 相册相关 framework | 0 个 |
      | `PrivacyInfo.xcprivacy` | 主 App 与扩展均已进包 |

      > ⚠️ `flutter build ipa` 会覆盖 `build/ios/ipa/RDesk.ipa`，build 11 的产物
      > 已经没了。日后要留证，打包前先把旧 IPA 另存。
- [ ] **上传 build 12 到 ASC**，并补出口合规
      （`./scripts/asc.py compliance 12`，见 app-store-submission.md 第七节——
      未回答出口合规的构建无法提交审核）
- [ ] **建一个测试账号并填进备注**。云设备页与「我的-我的设备」在未登录时只有
      登录墙（[cloud_devices_screen.dart:86](../flutter_client/lib/src/screens/cloud_devices_screen.dart:86)、
      [my_devices_screen.dart:207](../flutter_client/lib/src/screens/my_devices_screen.dart:207)），
      而上一轮备注声称「没有随账号变化的行为」「每个界面首次启动即可从标签栏到达，
      无前置条件」。审核员看不到这块功能，正好落在 5.6 的模板措辞上。
      账号可在 App 内「我的 → 注册」自助创建，无邀请码；建好后填入第二、三节的
      `<填入测试账号>` / `<填入测试账号密码>`。
      > 该账号下**不要**绑定任何私人设备，审核结束后删除。
- [ ] 用真实值替换下方所有 `<...>` 占位符
- [ ] 重跑 `./scripts/check_review_host.sh`（build 12 上传后、发送回复前）
- [ ] 用装有 **build 12** 的真机 iPhone 再实测一次：登录测试账号 → 云设备页
      能看到设备 → 退出登录 → 用设备 ID + 密码连接被控端

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

> **hostname 一致性是第一次被拒（08-07）的直接原因**，务必核对。
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
>
> 长度：3400 字符（含占位符，填入真实值后基本不变），在 4000 以内。
> 回复框上限未实测，按已实测的备注上限 4000 控制。
>
> **写法说明**：只写两条，且两条都能拿证据落地——
> 第一条是二进制里确证的问题（相册库有能力、界面无入口，build 12 已整套移除），
> 第二条是备注自身的疏漏（没给测试账号，还写了两句与实际不符的话）。
> 不辩解，也不再对 build 11 的其他行为下断言：复查中那些「看起来不符」的结论
> 有一半是验证方法错误造成的（见第四节「一次错误的复查」），而向 Apple 递交
> 一条捏造的「自我更正」，比不回复更糟。
>
> ⚠️ **发送前提**：build 12 已上传并补完出口合规，测试账号已建好并填入，
> 第一节阻塞项全部完成。

```
Thank you for the second review.

We audited our previous reply and our review notes against the binary you
reviewed, 2.1.0 (11). We found two things: one problem in the binary that we
believe matches your finding and have now removed, and one inaccuracy in our
notes.

1. A CAPABILITY THE INTERFACE GAVE NO WAY TO REACH

Build 11 shipped five frameworks - file_picker, DKImagePickerController,
DKPhotoGallery, SDWebImage, SwiftyGif - along with
NSPhotoLibraryUsageDescription. DKImagePickerController is a complete photo
picker interface. No line of our code calls any of them: file transfer browses
only the app's own sandbox directories, through a browser we wrote ourselves.

So the binary carried the ability to reach the photo library while the interface
offered no way to get there. This was not deliberate. file_picker was added early
on, the feature it was intended for ended up implemented differently, and the
dependency was never removed. But we understand how that looks under Guideline
5.6, and we are not going to argue about it.

Build 2.1.0 (12) removes it entirely: all five frameworks are gone, the app
declares no photo library permission, and the IPA is 1.2 MB smaller. The app has
no ability to access the photo library.

2. OUR NOTES GAVE YOU NO ACCOUNT, AND DESCRIBED THE APP AS IF NONE WAS NEEDED

We wrote that no behavior varies by account, and that every screen is reachable
from the tab bar on first launch with no preconditions. That was not accurate.
The "Cloud Devices" tab and "My Devices" under the "Me" tab show a sign-in prompt
while signed out, and list the devices synced to that account once signed in. We
gave you a host device ID and password but no account, so you had no way to reach
those screens. A test account is below and in our updated notes.

WHAT WE RE-VERIFIED, AGAINST BOTH THE SOURCE AND THE SHIPPED BINARY

- No embedded browser or web view; nothing loads remote HTML or scripts.
- No remote configuration and no feature flags. Our server exposes only account,
  device-presence, screen-frame, input, clipboard and file endpoints; no response
  from it enables, unlocks or alters any part of the UI.
- No debug menu, no tap-count or long-press unlock, no behavior that varies by
  region or date.
- No dynamic code loading, no custom URL schemes, no background modes.
- Two switches that reported success without doing anything ("privacy screen" and
  "record") were removed in build 11. We confirmed their strings are absent from
  both binaries.
- Apart from the two account-gated screens described above, every screen is
  reachable from the tab bar on first launch.

TEST ACCOUNT AND DEMO HOST

  Account:   <填入测试账号>
  Password:  <填入测试账号密码>

  Host:      OnePlus PLU110, Android 16, a physical phone we own
  Host name shown in the app: PLU110
  Device ID: 660725198
  Password:  <填入被控端密码>

The host stays powered on, charging and online for the review. Step-by-step
connection instructions and a complete list of every control in the session
screen are in our App Review notes.

IF SOMETHING ELSE WAS MEANT

Your message describes the finding in general terms, and the two items above are
what we found by auditing ourselves. If your finding refers to a specific feature
or screen we have not addressed, please tell us which one and we will answer it
directly. We would also welcome a phone call if that is faster.

Thank you for your time.
```

---

## 三、替换后的 App 审核备注（英文，覆盖原备注）

> ⚠️ **ASC 备注上限 4000 字符**。实测依据：2026-08-13 在 ASC 页面读取该 textarea，
> `maxLength` 属性为 -1（无硬限制），但现有备注 1429 字符时计数器显示剩余 2,571，
> 1429 + 2571 = 4000。
>
> 本节下方的「完整版」有 7883 字符，**装不进去**，只作为素材保留。
> **实际粘贴用下面的压缩版**（3936 字符，填入三个占位符后约 3940，余量约 60——
> 余量很窄，再往里加任何一句都要先数字符）。
>
> 压缩时保留了回应 Guideline 5.6 所必需的三块：测试账号与账号门控的如实说明、
> 会话页全部控件清单、「无隐藏功能」逐条声明。被压掉的是重复表述。

### 三之一、压缩版（粘贴这份）

```
Build under review: 2.1.0 (12).

TEST ACCOUNT

  Account:   <填入测试账号>
  Password:  <填入测试账号密码>

Sign in under the "我的" (Me) tab. The "云设备" (Cloud Devices) tab and "我的设备" (My Devices) show a sign-in prompt while signed out, and list the account's synced devices once signed in. They are the only functionality needing credentials; everything else works signed out.

DEMO HOST

A physical Android phone we own, kept powered on and online for the review:

  Host:        OnePlus PLU110, Android 16 — a real phone, not an emulator or a VM
  Host name shown in the app: PLU110
  Screen:      661 x 1440
  Device ID:   660725198
  Password:    <填入被控端密码>

RDesk is installed in a separate Android user profile holding no personal data. Unattended access is on, so nobody approves on the host side.

TO CONNECT

1. Tap "远程连接" (Remote Connection) in the bottom tab bar.
2. Enter the Device ID in "设备代码" and the Password in "验证码", keep the default mode "远程控制" (Remote Control), tap "密码连接".
3. The remote screen appears. Tap = tap, long press = long press, drag = swipe on the host; a two-finger pinch zooms this device's view only.

EVERY CONTROL IN THE SESSION SCREEN

There is no other menu, gesture or entry point in this screen.

Bottom bar: 返回 Back | 主页 Home | 任务 Recents | 键盘 types text into the focused field on the host | 操作 opens the sheet below.

Sheet, toggle row: 退出远控 ends the session | 仅观看 view-only, sends no input of any kind while on | 指针模式 draws a pointer on the local view; three buttons send tap, long press or drag there | 旋转画面 rotates this device's view by 90 degrees per tap | 全屏 hides the iOS status bar | 隐藏工具栏 hides the bottom bar; a top-right button brings it back.

Sheet, 操作 group: 滚动 上滑/下滑 swipe up or down | 删除 deletes one character | 回车 sends Enter | 唤醒屏幕 wakes the host display.

Sheet, 剪贴板 group: 发送到远端 and 从远端获取 exchange clipboard text.

Sheet, 更多 group: 画质设置 requests quality and frame rate | 显示器 switches monitor | 文件传输 | 会话聊天.

仅观看, 指针模式, 旋转画面, 全屏 and 隐藏工具栏 change only what this device shows or sends; every other control results in a request to the host. Every control does what its label says: no switch reports success without acting.

NO HIDDEN OR REMOTELY ENABLED FUNCTIONALITY

No web view; nothing loads remote HTML or scripts. No remote configuration and no feature flags: our server exposes only account, device-presence, screen-frame, input, clipboard and file endpoints; no response from it alters the UI. No debug menu, no tap-count unlock, no behavior varying by region or date. No dynamic code loading, no custom URL schemes, no background modes. Apart from the two account-gated screens above, every screen is reachable from the tab bar on first launch.

GUIDELINE 4.2.7

The app connects only to devices the user owns or is authorized to access. It does not provide, host or resell any virtual machine, cloud desktop or remote computer, and offers no app store on the host. All displayed content comes from the user's own host. Remote control applies to macOS and Android hosts; an iOS host can only share its screen, as the app states.

PERMISSIONS AND TRANSPORT

Screen capture on iOS uses a ReplayKit Broadcast Extension and starts only when the user selects RDesk in the system screen-recording menu. The app declares no photo library permission and never accesses it; file transfer browses only its own sandbox directories. The default server is https://qisw.top, so sign-in, screen data and input events travel over HTTPS/WSS. Info.plist sets NSAllowsArbitraryLoads because users may point the app at their own self-hosted server or a LAN IP, which cannot be enumerated in advance. Screen data relayed through our server is readable there; we do not claim end-to-end encryption, and our privacy policy says so.

Account deletion is in-app under "我的" (Me) → "注销账号".

If the app reports no online device, the host is briefly offline — contact us at 641742030@qq.com and we will restore it.
```

### 三之二、完整版（素材，勿直接粘贴——超出 4000 字符）


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

Build under review: 2.1.0 (12)

TEST ACCOUNT

  Account:   <填入测试账号>
  Password:  <填入测试账号密码>

Sign in under the "我的" (Me) tab. Signing in populates the "云设备" (Cloud
Devices) tab and "我的设备" (My Devices) under "我的": both show a sign-in
prompt while signed out, and list the devices synced to that account once
signed in. These two screens are the only functionality in the app that
requires credentials to see; everything else works signed out.

Account deletion is available in-app under "我的" (Me) → "注销账号".

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
- No remote configuration and no feature flags. Our server exposes only
  account, device-presence, screen-frame, input, clipboard and file endpoints,
  and no response from it enables, unlocks, or alters any part of the UI.
- No debug menu, no tap-count or long-press unlock, no behavior that varies by
  region or date.
- No dynamic code loading. No custom URL schemes. No background modes.
- Apart from the two account-gated screens described under TEST ACCOUNT, every
  screen is reachable from the tab bar on first launch.
- Every control in the session screen is enumerated above, including the ones
  that only affect local display.

CONNECTION SECURITY

- The host must actively start sharing and set a password. The client must
  supply the correct password to connect.
- In this build the default server is https://qisw.top, so traffic between the
  app and our server (sign-in, screen data, input events) travels over
  HTTPS / WSS.
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

PHOTO LIBRARY

The app declares no photo library permission and never accesses the photo
library. File transfer browses only the app's own sandbox directories through a
file browser we implemented ourselves; it does not open the system photo
picker.
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

---

### 二拒复查（2026-08-14）

第二次被拒后做了两轮复查。**第一轮的结论有一半是错的**，先记结论，再记怎么错的。

#### 确证的两个问题

**一、build 11 带着界面上够不到的相册能力。**

| 项 | 证据 |
|---|---|
| 包内 framework | `file_picker`、`DKImagePickerController`、`DKPhotoGallery`、`SDWebImage`、`SwiftyGif`——`DKImagePickerController` 是整套相册选择界面 |
| `Info.plist` | 含 `NSPhotoLibraryUsageDescription` |
| 代码调用 | `grep -rn "file_picker\|FilePicker" lib/` **无任何结果** |
| 实际的文件传输 | 自建沙盒目录浏览器（[file_manager_screen.dart](../flutter_client/lib/src/screens/file_manager_screen.dart)），不碰相册 |

App 有能力、界面无入口，这是对 "features that appear to have been intentionally
hidden during the review process" 最贴合的解释，且静态扫描很容易发现。
build 12 已整套移除，IPA 从 23.1MB 降到 21.9MB。

**二、备注没给测试账号，还写了两句与实际不符的话。**
云设备页与「我的-我的设备」未登录时只有登录墙
（[cloud_devices_screen.dart:86](../flutter_client/lib/src/screens/cloud_devices_screen.dart:86)、
[my_devices_screen.dart:207](../flutter_client/lib/src/screens/my_devices_screen.dart:207)），
备注却称「没有随账号变化的行为」「每个界面首次启动即可从标签栏到达，无前置条件」。
审核员拿不到账号，这块功能对他不存在。

#### 一次错误的复查——两个验证方法都是错的

第一轮曾得出「备注还有三条声明与 build 11 不符」，其中**两条纯属误判**，
若照那版文案发出去，等于向 Apple 递交两条捏造的「自我更正」。成因是两个
看起来都很合理、实则都不成立的验证方法：

**错误一：拿 `git diff` 当成 build 的内容依据。**
当时 `constants.dart`（https）、`profile_screen.dart`（注销账号）、
`Info.plist`（相册键）都是未提交的工作区改动，于是判定 build 11 不含它们。
**但打包读的是工作区文件，不是 HEAD。** 实测 build 11 的 IPA 里，
相册键在、注销账号在、https 也在——那批改动早就打进去了。

**错误二：用 UTF-8 的 grep 在 Dart AOT 快照里搜中文字符串。**
`grep -a '注销账号' App.framework/App` 返回 0，据此判定 build 11 缺注销入口。
实际上 Dart 的 `String` 分 OneByteString（Latin-1）与 TwoByteString，
**中文走 TwoByteString，在快照里按 UTF-16 存**，UTF-8 的 grep 永远搜不到。
换成 UTF-16LE 重查，build 11 与 build 12 的计数逐项相同：

```python
data = open('App.framework/App','rb').read()
data.count('注销账号'.encode('utf-16-le'))   # 两个包都是 1
data.count('隐私屏'.encode('utf-16-le'))     # 两个包都是 0（空开关确已删除）
```

两个包的 Dart 二进制大小完全相同（7573 KB），所有字符串计数一致——
**build 11 与 build 12 的 Dart 代码本就相同**，差异只在原生依赖与版本号。

**另一个到现在也没能验证的问题**：默认服务器是 `qisw.top:80` 还是
`https://qisw.top`，无法从二进制区分。因为 `_legacyServerSettings` 那个迁移用的
旧值集合本身就同时含这两个字符串，Dart 又会把相同字符串常量合并去重。
**所以回复稿里不对 build 11 的传输方式下任何断言**——这类查不出来的事，
就不要写进给 Apple 的文字里。

> ⚠️ `flutter build ipa` 会覆盖 `build/ios/ipa/RDesk.ipa`。build 11 的产物在
> 打 build 12 时被覆盖掉了，上面的证据是覆盖前取出的。以后打包前先另存旧 IPA。

#### 复核仍然成立的部分（不必改口）

| 检查项 | 结果 | 依据 |
|---|---|---|
| 服务端下发功能开关 | 无 | 服务端路由只有 account / preview / input / clipboard / file / ws 几组，无任何 config 类接口 |
| 自定义 URL scheme、后台模式 | 无 | `Runner/Info.plist` 无 `CFBundleURLTypes`、无 `UIBackgroundModes` |
| WebView、动态代码加载 | 无 | 依赖表无 `webview_flutter` / `url_launcher`；Rust + Flutter AOT |
| 面板控件与被控端实现对得上 | 是 | `back/home/recents/scroll_up/scroll_down/delete/enter` 见 [RdeskAccessibilityService.kt:44](../flutter_client/android/app/src/main/kotlin/com/qsw/rdesk/RdeskAccessibilityService.kt:44)；`wake_screen` 见 [android_host_provider.dart:622](../flutter_client/lib/src/providers/android_host_provider.dart:622) |
| 空开关 | 已清除 | `0b0ecc9`；UTF-16LE 检索确认「隐私屏」「录屏已开始」在 build 11 与 12 中均为 0 次 |

#### 教训

**一、声明的依据必须来自「即将提交的那个包」，不是源码，更不是 diff。**
第一次被拒是备注与演示环境对不上，二拒复查又栽在拿 diff 推断包内容。
能解压 IPA 就解压 IPA：`Info.plist`、`Frameworks/` 列表、`App.framework/App`
里的字符串，都是可直接读的事实。

**二、验证方法本身也要验证。**
一个返回 0 的搜索，先确认它在「应该有」的样本上能返回非 0，再拿它下结论。
若当初先用 build 12（明确含注销账号）验一下 grep，立刻就能发现编码问题。

**三、查不出来的事，不要写进给 Apple 的文字里。**
默认服务器那条查不动，就不写。写全称判断（no… / every… / all…）之前先
grep 一遍，grep 不动就改成有保留的表述。

**四、不要用一次错误的自我更正去补一次错误的声明。**
5.6 本就是冲着「说的和做的不一致」来的，主动认错只有在认的确实是错的时候才有用。