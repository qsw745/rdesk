# RDesk iOS 上架材料

本文档汇总 App Store 提交所需的全部信息，供在 App Store Connect 逐项填写。

- **Bundle ID**：`com.qsw.rdesk`
- **Team ID**：`6N5T3G6H33`
- **版本 / 构建号**：**2.1.0 (6)** —— 提交时必须选此构建
  （由 `flutter_client/pubspec.yaml` 的 `version: 2.1.0+6` 统一管理）

---

## 一、最高风险项：审核员无法测试

远程桌面 App 需要**两台设备**才能演示核心功能，而审核员通常只有一台 iOS 设备。
若不提供可连接的被控端，审核大概率以「无法完成审核」被拒。

**提交前必须准备：一台常开的演示被控端。**

- 在一台 Windows / macOS 上运行 RDesk 被控端，保持开机联网
- 设置一个**永久密码**（不要用一次性临时密码，审核可能跨越数天、多次尝试）
- 将「设备 ID + 永久密码」写入下方审核备注

### ⛔ 旧演示环境（Android 模拟器）—— 已废弃，不要再用

2026-08-07 因 **Guideline 5.6** 被拒，直接原因就是这套环境。详见
[app-review-response.md](app-review-response.md)。

曾使用本机 Android 模拟器（AVD `RDeskDemo`，设备 ID `927 251 902`）。
当时的想法是「模拟器不含个人数据、环境干净」，但它带来两个致命问题：

1. **模拟器会如实上报自己的身份**：`hostname=sdk_gphone64_arm64`、
   `ro.build.characteristics=emulator`、`ro.kernel.qemu=1`。
   客户端把 hostname 显示在会话页标题，而审核备注却写着「该演示设备为
   Android 手机」——审核员看到的与我们的声明直接矛盾。
2. **让审核员连虚拟机违反 Guideline 4.2.7**（远程桌面客户端不得提供
   虚拟机/云主机），而同一份备注里还写着「不提供任何云端主机或虚拟机服务」。

该 AVD 已于 2026-08-07 关闭，服务端查询返回 `found:false`，密码 `Review2026` 作废。

### 演示环境的硬性要求

- **必须是真实物理设备**（真机 Android / 真实 Windows / 真实 macOS），
  不能是模拟器、虚拟机或云主机
- 审核备注里对设备的每一句描述，都必须与审核员实际看到的标识符一致 ——
  跑 `./scripts/check_review_host.sh`，它会打印服务端返回的
  `hostname` 与 `platform`，并在检出模拟器标识时直接判失败
- 永久密码，审核期间不改
- 开启无人值守，免去被控端手动确认

**维持该环境需要注意：**

提交后**每天跑一次**下面的检查脚本。它覆盖审核员实际走的完整链路
（模拟器在线 → 录屏/无障碍授权 → 服务端解析鉴权 → 画面推送 → 隐私/支持页可访问），
任一环节断掉都会直接输出修复命令；退出码 0 表示审核员可正常连接。

```bash
./scripts/check_review_host.sh
```

```bash
# 若模拟器已关闭，重新启动（审核期间须保持运行）
~/Library/Android/sdk/emulator/emulator -avd RDeskDemo -no-audio -no-boot-anim &
```

- **Mac 必须保持开机且不休眠**（系统设置 → 锁定屏幕 → 显示器关闭后 → 永不），
  否则模拟器掉线，审核员连不上会直接以 Guideline 2.1 打回
- 模拟器重启后设备 ID 不变，但**录屏授权会被系统回收**，需重新进入
  「我的 → 移动被控」点一次「去授权」并确认系统弹窗
- 审核通过后建议删除该 AVD 或至少改掉永久密码
- 审核期间（提交后约 1–7 天）**不要关机、不要改密码**

> 若无法提供常开主机，替代方案是录制一段完整操作视频上传到可公开访问的链接
> （YouTube 不限速地区 / 自有服务器），并在备注中给出。但这属于次优方案，
> Apple 仍可能坚持要求可实际操作的环境。

---

## 二、审核备注（App Review Information → Notes）

> ⛔ **本节内容已作废，不要再粘贴。**
> 其中「该演示设备为 Android 手机」与实际的模拟器环境不符，
> 是 2026-08-07 触发 Guideline 5.6 的直接原因。
>
> **改用 [app-review-response.md](app-review-response.md) 第三节的英文备注**，
> 那一版已改为真实 Windows 主机，并补充了「无隐藏功能」的逐条声明。
> 以下内容仅作历史记录保留。

<details>
<summary>已作废的旧备注（点击展开）</summary>

以下内容**不要使用**：

```
【测试环境】
RDesk 是远程桌面客户端，需要一台被控设备才能演示完整功能。
我们已准备好一台常开的 Android 演示设备，审核期间保持在线：

  设备 ID：927 251 902
  连接密码：Review2026

该设备已开启无人值守模式，无需对方手动确认即可接入。

操作步骤（以下步骤已实测验证）：
1. 打开 App，点击底部标签栏的「远程连接」
2. 在「设备代码」输入框填入上述设备 ID
3. 在「验证码」输入框填入上述连接密码
4. 保持模式为「远程控制」（默认已选中）
5. 点击蓝色的「密码连接」按钮
6. 连接建立后即显示远程桌面画面，顶部工具栏提供返回/主页/任务/
   输入/回车等操作，单击发送点击、长按发送长按、双指捏合缩放画面

该演示设备为 Android 手机，屏幕分辨率 706×1440。
连接后可通过顶部工具栏的「返回」「主页」「任务」直接操作被控端的系统界面。

若显示「未找到在线设备」，说明演示设备临时离线，
请通过 641742030@qq.com 联系我们，我们会立即恢复。

【关于 Guideline 4.2.7 远程桌面客户端】
- 本 App 仅连接用户本人拥有并已授权的设备，不提供任何云端主机或虚拟机服务
- 所有显示内容均来自用户自己的被控设备，App 本身不托管任何内容
- 不在被控端提供任何第三方应用商店，也不下载或执行任何外部代码

【关于连接安全】
- 被控端必须由用户主动启动共享并设置密码，主控端需提供正确密码方可连接
- App 与服务器之间的全部通信（账号登录、画面数据、控制指令）均通过
  HTTPS / WSS 加密通道传输
- 经服务器中转时，画面数据在服务器上可解析；本 App 目前尚未实现端到端加密。
  该边界已在隐私政策中向用户明确说明
- 同一局域网内可使用直连地址，此时数据不经过我们的服务器
- 用户可随时在被控端断开会话

【关于 App Transport Security】
Info.plist 中设置了 NSAllowsArbitraryLoads。原因：
默认服务器地址为 https://qisw.top，正常使用走 HTTPS。
但本 App 允许用户填写自建的中继/信令服务器地址，也支持直接连接局域网内的
IP 地址（如 192.168.x.x）。这类地址由用户在运行时输入，无法预先枚举为
域名例外，且局域网设备通常没有可信证书，因此需要该项以支持自托管场景。

【录屏权限说明】
iOS 端作为被控端时使用 ReplayKit Broadcast Extension 采集屏幕。
该能力必须由用户在系统录屏菜单中手动选择 RDesk 才会启动，
App 无法在用户不知情的情况下开始采集。

需要说明的是，受 iOS 系统限制，本 App 在 iOS 被控端上
**仅能共享屏幕画面，无法接受远程触控操作**。
远程操控能力仅适用于 Windows / macOS / Android 被控端。
App 内「iOS 被控」页面已向用户明确标注该限制。

【相册权限说明】
Info.plist 中声明了 NSPhotoLibraryUsageDescription。
该权限用于文件传输功能——用户可选取本地图片发送到远程设备。
权限由文件选择器在用户主动点击「文件传输」后才会触发申请，
App 不会在后台读取相册。
```

</details>

---

## 三、App 隐私问卷（App Privacy）

> **重要更正**：早期版本的本文档写的是「不收集数据」，这是**错误**的。
> 那个结论只核对了 `PrivacyInfo.xcprivacy`（记录 SDK 层面的受限 API 使用），
> 没有核对业务层代码。App 实际存在账号体系，会上传数据。
> 隐私问卷虚假申报是上架后被下架的常见原因，必须按下表如实填写。

### 必须申报为「收集数据」

依据代码：
- [`rdesk_bridge_service.dart:920`](../flutter_client/lib/src/services/rdesk_bridge_service.dart)
  `/api/account/register` 提交 `username`、`password`、`display_name`
- [`rdesk_bridge_service.dart:936`](../flutter_client/lib/src/services/rdesk_bridge_service.dart)
  `/api/account/login` 提交 `username`、`password`
- `listAccountDevices()` 从服务端拉取该账号下的设备列表，
  说明设备标识已上报服务端

| 数据类型 | ASC 分类 | 用途 | 关联身份 | 用于追踪 |
|---|---|---|---|---|
| 账号用户名 | Contact Info → Name（若允许手机号注册，还需勾 Phone Number） | App Functionality | 是 | 否 |
| 用户 ID / 会话令牌 | Identifiers → User ID | App Functionality | 是 | 否 |
| 设备 ID | Identifiers → Device ID | App Functionality | 是 | 否 |

**是否用于追踪（Tracking）：否** —— 不做跨 App/网站的广告或数据经纪共享。

### 填写要点

- 账号功能是**可选**的：不登录也能用设备码直连。ASC 问卷中可勾选
  「Data is only collected in optional scenarios」类说明
- 密码不属于需申报的收集项（用于认证、不做他用），但**不得**因此
  把整体答成「不收集」
- 以下确实**不上传**，可在问卷中排除：
  - 账号凭据、设备密码存于 `flutter_secure_storage`（iOS Keychain），仅本机
  - 连接记录、信任设备列表存于本地 `SharedPreferences`
  - 会话画面经服务器中转时不作持久化存储，转发后即从内存丢弃
    （注意：服务器技术上可访问画面内容，不能声称「无法解密」）

> 若后续接入统计或崩溃上报 SDK，需在此表继续追加对应条目。

---

## 四、出口合规（Export Compliance）

App 自身未实现独立的加密算法，加密只用于 HTTPS / WSS 传输。

> **更正（2026-08-06）**：本节此前写的是「加密仅来自**系统** TLS」，这是**错的**，
> 不能作为出口合规问卷的依据。
>
> Flutter 客户端走 `dart:io` 的 `HttpClient` / `WebSocket`，而 Dart VM 的 TLS
> 由 **Flutter 引擎内置的 BoringSSL** 提供，并非 Apple 的 Security / SecureTransport。
> 已实测确认：
>
> ```bash
> FR=$(grep -m1 '^FLUTTER_ROOT=' flutter_client/ios/Flutter/Generated.xcconfig | cut -d= -f2)
> strings "$FR/bin/cache/artifacts/engine/ios-release/Flutter.xcframework"/*/Flutter.framework/Flutter \
>   | grep -ciE 'BORINGSSL|OPENSSL|SSL_CTX'
> ```
>
> 结果：`BORINGSSL` / `OPENSSL` / `SSL_CTX` 均命中，`SecureTransport` 无命中。
>
> 因此在 ASC「App 加密文稿」的第一问中，**不能选「不属于上述任意一种算法」**——
> App 二进制里确实带了标准加密实现。应选「代替在 Apple 操作系统中使用或访问加密，
> 或与这些操作系统同时使用的标准加密算法」，再在后续豁免问题中判断。
>
> 另注：`crates/rdesk_crypto` 的 Noise 实现只被 `rdesk_core` 使用，
> Flutter 客户端不调用，**不要以 Noise 为依据**。

**已踩过的坑**：曾在 `Info.plist` 声明 `ITSAppUsesNonExemptEncryption = true`，
上传直接被拒，错误码 **90592**：

```
Invalid Export Compliance Code. The export compliance key value [] in the app's
Info.plist doesn't match the key value of the app's export compliance documentation.
```

原因：声明 `true` 后，Apple 要求同时提供 `ITSEncryptionExportComplianceCode`，
而该码需先向美国 BIS 申请 ERN/CCATS 才能取得。

**当前做法**：`Info.plist` 中不声明该键，改为在 App Store Connect 的出口合规
问卷中回答。这样不预设任何申报结论，由负责人在 ASC 的官方引导下判断。

**三种可选路径**：

| 方案 | 代价 |
|---|---|
| 申请 ERN / CCATS 取得合规码 | 合规最完整，需数天～数周 |
| 声明 `ITSAppUsesNonExemptEncryption = false` | 立即可传，属豁免申报，需自行做法律判断 |
| 不声明该键（当前采用） | 立即可传，每次上传后在 ASC 回答问卷 |

> 这是法律申报事项，责任由申报方承担。若日后取得合规码，
> 可在 `Info.plist` 中补充上述两个键以免去重复回答。

---

## 五、商店信息

### 名称与副标题
- **App 名称**（≤30 字符）：`RDesk 远程桌面`
- **副标题**（≤30 字符）：建议 `安全的跨平台远程控制`

### 关键词（≤100 字符，逗号分隔，不加空格）
```
远程桌面,远程控制,远程协助,屏幕共享,远程连接,远程办公,文件传输,局域网,跨平台
```

> **已移除两个高风险词**：
> - `teamviewer` —— competitor 商标。Apple 禁止在元数据中使用他人品牌名
>   （Guideline 5.2.1 侵犯知识产权），这是明确的拒审项，且可能招致商标投诉。
> - `内网穿透` —— 本 App 无 NAT 穿透实现（无 STUN/ICE），属虚假宣传。

### 描述草稿

```
RDesk 是一款安全、高效的跨平台远程桌面控制工具，让你随时随地访问自己的电脑。

【核心功能】
· 远程控制 —— 实时查看并操控远程设备屏幕，支持鼠标、键盘与多点触控手势
· 多显示器 —— 自由切换远程设备的多个屏幕
· 画质调节 —— 可按需调整画面清晰度，在流畅与清晰之间取舍
· 文件传输 —— 在本机与远程设备之间双向传输文件
· 剪贴板同步 —— 文本内容在两端自动同步

【安全设计】
· 传输加密 —— 与服务器之间的全部通信经 HTTPS / WSS 加密通道传输
· 密码认证 —— 被控端需主动开启共享并设置密码，验证通过才能连接
· 生物识别 —— 支持 Face ID 快速登录
· 局域网直连 —— 同一网络内可直连，画面数据不经过服务器

【连接方式】
同一局域网内可填写对方的直连地址，延迟更低且数据不经服务器；
跨网络时通过中继服务器转发。

【跨平台】
支持 Windows、macOS、Android、iOS 之间互控。

注意：使用本 App 需要在被控设备上安装并启动 RDesk 被控端，
且仅可用于连接你本人拥有或已获得明确授权的设备。
```

### 功能核实对照表

上面的文案是逐条核对代码后写的。宣传未实现的功能属于虚假宣传，
既可能被拒审，也可能在上架后被用户投诉。**改文案前请先核实实现**。

| 宣传点 | 实现状态 | 依据 |
|---|---|---|
| 远程控制 | ✅ 有 | 已实测连接成功 |
| 多显示器 | ✅ 有 | `desktop_host_provider.dart` `/displays`、`list_displays` |
| 画质调节 | ⚠️ 仅手动 | `setJpegQuality()` 经 `/settings/quality` 调用；**无**基于网络的自动调节 |
| 文件传输（双向） | ✅ 有 | `uploadFile()` / `downloadFile()` |
| 文件断点续传 | ❌ 无 | 无 Range/offset/resume 相关实现 |
| 剪贴板同步（文本） | ✅ 有 | `session_provider.dart` `sendClipboard()` |
| 剪贴板同步（图片） | ❌ 无 | 仅处理 `text/plain` |
| 会话聊天 | ❌ 形同虚设 | `sendChatMessage()` 只写本地存储，从不发往对端 |
| 端到端加密 | ❌ 无 | Flutter 端无任何 noise/chacha/x25519 调用 |
| 前向保密 | ❌ 无 | 无密钥协商实现 |
| 传输加密 | ✅ 有 | 默认 `https://qisw.top`，WS 自动切 `wss` |
| 密码认证 | ✅ 有 | 被控端密码校验 |
| 生物识别 | ✅ 有 | `local_auth` |
| P2P NAT 穿透 | ❌ 无 | 无 STUN/ICE/打洞实现 |
| 局域网直连 | ✅ 有 | `remote_assist_screen.dart` 直连地址 |
| Linux 支持 | ⚠️ 未验证 | 存在 `linux/` 目录可构建，但未实测运行 |

> 已从文案中移除：端到端加密、前向保密、会话聊天、断点续传、
> 剪贴板图片同步、P2P 自动回退、Linux 平台。

### 必填链接
- **隐私政策 URL**：`https://qisw.top/rdesk/privacy` —— **已部署上线**

  部署方式（服务器 101.37.21.147）：
  - 页面源文件：仓库内 [`deploy/privacy.html`](../deploy/privacy.html)
  - 服务器路径：`/data/website/rdesk/privacy.html`
    （挂载到 nginx 容器 `/usr/share/nginx/html`）
  - nginx 配置：`/opt/nginx/conf.d/site.conf` 的 80 与 443 两个 server 块中
    各有一条 `location = /rdesk/privacy`，改动前备份为 `site.conf.bak-privacy-20260731`
  - 更新内容后需重新上传并执行 `docker exec nginx nginx -s reload`

  > 内容须与隐私问卷保持一致。本页已按「收集账号信息」如实撰写，
  > 与第三节的申报口径对应。
- **技术支持 URL**：`https://qisw.top/rdesk/support` —— **已部署上线**

  源文件 [`deploy/support.html`](../deploy/support.html)，
  服务器路径 `/data/website/rdesk/support.html`，
  nginx 中 80 / 443 各有一条 `location = /rdesk/support`
  （备份 `site.conf.bak-support-20260804`）。

  内容涵盖：快速开始、常见问题（设备离线、macOS 黑屏需授权、
  iOS 只能共享不能被控、延迟指标的含义、忘记密码、注销账号）、
  安全边界说明、联系邮箱。

  > 部署后立即 curl 可能返回 404 —— `nginx -s reload` 是异步的，
  > 等几秒再验证。

- **营销 URL**：选填

### 分级
建议年龄分级 **4+**（无不适宜内容）。

---

## 六、截图要求

以本 App 的 ASC 页面实际显示为准：

| 设备类别 | 分辨率（任选其一） | 数量 |
|---|---|---|
| iPhone 6.5 英寸显示屏 | 1242×2688、2688×1242、1284×2778、2778×1284 | 1–10 张 |
| iPad（已确认保留 iPad 支持，必填） | 见 ASC「媒体管理」中的 iPad 尺寸要求 | 1–10 张 |

> 只有**前 3 张**截屏会显示在 App 安装表中，把最有说服力的放前面。
> 已确认保留 `TARGETED_DEVICE_FAMILY = "1,2"`（支持 iPad），因此 iPad 截图为必填项。

建议截图内容：首页设备列表 / 连接中的远程画面 / 手势操作 / 文件传输 / 安全设置。

---

## 七、已上传构建版本

| 构建号 | 结果 |
|---|---|
| 2.1.0 (4) | 上传成功，但被 Apple 邮件退回：**ITMS-90683** 缺少 `NSPhotoLibraryUsageDescription` |
| 2.1.0 (5) | 上传成功，已补相册用途说明 |
| 2.1.0 (6) | 上传成功。**应提交此版本**：默认服务器改为 HTTPS、新增应用内注销账号、更换 App 图标 |

### build 6 的三项关键变更

1. **默认服务器改为 HTTPS**（`https://qisw.top`）
   旧版默认 `qisw.top:80`，账号密码与屏幕画面均明文传输。
   `qisw.top:80` 已加入 `_legacyServerSettings`，已安装用户在下次启动时自动迁移。
2. **应用内注销账号**（App Store 审核指南 5.1.1(v) 强制要求）
   服务端 `/api/account/delete`（需密码二次校验），客户端「我的 → 安全中心 → 注销账号」。
3. **更换 App 图标** —— 此前是 Flutter 默认 logo，属他人商标且会被判定为未完成的 App。

### ITMS-90683 的成因

`file_picker` 依赖的 `DKImagePickerController` / `DKPhotoGallery` 引用了
`PHAsset`、`UIImagePickerController`，即使本 App 不主动读取相册，
Apple 的静态扫描仍要求提供用途说明。

排查方式（扫描二进制中引用的受保护 API）：

```bash
cd build/ios/iphoneos/Runner.app
for k in PHPhotoLibrary PHAsset AVCaptureDevice UIImagePickerController; do
  printf "%-24s " "$k"
  (strings Runner; for f in Frameworks/*.framework/*; do [ -f "$f" ] && strings "$f"; done) \
    | grep -qw "$k" && echo "引用" || echo "-"
done
```

结果：`PHAsset` 与 `UIImagePickerController` 有引用，`AVCaptureDevice` 无引用，
因此只需补相册权限，**不需要**相机权限（少要一个权限对审核更有利）。

## 八、已知警告（不阻塞上架）

**Upload Symbols Failed — `objective_c.framework` 缺少 dSYM**

该 framework 经 Dart native assets 机制引入（不在 `Podfile.lock` 中），
Flutter 工具链目前不为其生成 dSYM。所有 CocoaPods 依赖的 dSYM 均正常。

影响：仅该 framework 的崩溃日志无法符号化。不影响审核与上架，
非项目配置问题，无需处理。

## 九、提交前检查清单

- [x] 自有 `PrivacyInfo.xcprivacy`（主 App + 录屏扩展）
- [x] 扩展与主 App 的 CFBundleVersion 一致
- [x] 第三方 SDK 隐私清单齐全（13 个依赖均自带）
- [x] Apple Distribution 证书与 App Store 描述文件
- [x] 构建版本已上传（**2.1.0 build 6**，提交时须选此版本）
- [x] App 图标已替换（此前是 Flutter 默认 logo）
- [x] 应用内注销账号入口（5.1.1(v) 强制要求）
- [x] 默认服务器改 HTTPS，已安装用户自动迁移
- [x] 隐私政策 URL 可访问（`https://qisw.top/rdesk/privacy`）
- [x] 技术支持 URL 可访问（`https://qisw.top/rdesk/support`）
- [x] 截图已重做（去除 iPadOS 系统手柄、设备 ID 改示意值）
- [x] 商店文案已按代码逐条核实，移除未实现功能
- [x] 关键词已移除竞品商标 `teamviewer` 与不实的 `内网穿透`

**App Store Connect 网页端（2026-08-06 已完成）：**

- [x] **版本号改为 2.1.0**（默认创建的是 1.0，不改则选不到 build 6）
- [x] 构建版本选定 2.1.0 (6)
- [x] 出口合规问卷 —— 第一问选**「标准加密算法」**（不是「不属于上述任意一种」，
      依据见第四节的 BoringSSL 实测）；第二问「是否在法国分发」答**否**
- [x] App 隐私问卷 —— 答「收集数据」，姓名 / 用户 ID / 设备 ID，
      均为 App 功能 + 关联身份 + 不用于追踪，**已发布**
- [x] 隐私政策 URL 与技术支持 URL
- [x] 截图（iPhone 6.5" 4 张、iPad 13" 2 张）
- [x] 副标题、主要类别（工具）、描述、关键词
- [x] 年龄分级问卷 → **4+**
- [x] 定价：免费
- [x] 供应范围：**148 个国家/地区**，精确排除欧盟 27 国
      （未提交 DSA「交易商状态」，故暂不在欧盟分发；
      保留英国、瑞士、挪威、冰岛、土耳其等非欧盟欧洲国家）
- [x] 审核备注 + 联系信息；「需要登录」取消勾选（设备码直连不需账号）
- [x] 发布方式：审核通过后自动发布
- [x] 版权：版本页「版权」栏填 `2026 祁世伟`；
      App 信息「内容版权」答**否**（App 不附带第三方内容，画面来自用户自己的设备）
      —— 这两项缺失会在点「添加以供审核」时直接拦截，容易漏
- [x] 演示被控端就绪（`./scripts/check_review_host.sh` 全绿）
- [x] **已于 2026-08-06 11:46 提交审核**（iOS App 2.1.0 build 6，审核最长 48 小时）

### 欧盟分发的后续处理

本次为尽快上架，选择排除欧盟 27 国。若要覆盖欧盟，需在
「用户和访问 → 交易商状态」提交真实姓名、地址、电话并通过 Apple 核验，
核验通过后再把这 27 国加回供应范围即可，无需重新提交构建。
