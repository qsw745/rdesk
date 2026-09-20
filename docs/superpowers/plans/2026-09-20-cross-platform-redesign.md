# RDesk 跨平台改版实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans in this session. 用户已指定当前会话直接实现；由主代理执行，不另建任务、不自动分派子代理。

**Goal:** 修复 Windows 网卡检测误报，交付分平台的清晰界面、扁平设置，以及 iPhone / Android 扫码绑定 Windows 后通过家庭 Android 助手远程开机的完整流程。

**Architecture:** 保留 Flutter、现有账号与远控传输。原生 Windows 桥接负责网卡枚举；纯 Dart 目录模型汇总设备；平台能力决定导航和设置；新的短时配对协议接入已有 wake 目标、助手、心跳及开机回执。

**Tech Stack:** Flutter 3.41.4 / Dart 3.11.1、Windows C++ / IP Helper API、Rust / Axum、现有安全存储、qr_flutter 4.1.0、mobile_scanner 7.2.0。

**Spec:** `docs/design/2026-09-20-cross-platform-redesign.md`，用户已确认。

## Global Constraints

- 本计划待审阅，尚未开始产品代码改动。采用当前会话、主代理执行方式。
- 所有编译、打包、验证在本机或本地 Windows 虚拟机 / 容器完成；服务器只运行预构建成品。不得触发 GitHub Actions 或其他云端构建。
- 当前基线 `a5d691d`。先保存 `git diff --binary`、未跟踪文件清单及涉及文件副本到忽略目录 `.release-work/20260920/redesign-baseline/`；不回退、不混入已有捕获及审核修改。
- 涉及已有脏文件时逐段核对。提交只包含本任务修改；发行使用干净源码导出加已审阅提交，不直接打包整个工作区。
- Windows 仍是控制端；iPhone 是扫码及开机控制端，家庭 Android 是常驻发送助手。不得出现未实现的 Windows 被控开关。
- 不自动关机、重启用户正在使用的 Windows；睡眠、断电、隔夜等真实验收单独安排。
- 不提高现有 iOS 系统要求。Runner 项目配置为 13.0，Broadcast Extension 为 15.0，分别保持；读取最终产物确认，不把插件最低版本当成应用最终最低版本。
- App Store 上传、审核提交与官网安装包发布分开。当前授权覆盖开发、本地手机安装及已要求的自有网站发布，不宣称 iOS 商店版已更新。
- 已有登录、账户删除、设备历史、地址簿分组、直连、远控和文件功能保留。

## Review Focus

1. 查询失败不能显示为没有网卡；原生枚举错误、拔网线、虚拟接口分别验证。
2. 手机不得获得 Windows 长期心跳凭据；二维码不携带任意服务器地址或账户凭据。
3. 配对确认、目标创建、磁盘持久化必须一致；失败不得出现幽灵成功、重复目标或串账号。
4. 设备来源有无服务器范围时不能错误合并；旧历史/收藏不能静默归属当前账号。
5. 所有“已上线 / 已配置 / 已发送”均有相应证据；模拟协议通过不等于物理开机通过。

---

## 阶段 1：Windows 检测和可复制诊断

### Task 1：原生网卡枚举及错误模型

**文件**
- 新建：`flutter_client/windows/runner/wake_adapter_bridge.h`、`wake_adapter_bridge.cpp`。
- 修改：`flutter_client/windows/runner/flutter_window.cpp`、`flutter_window.h`、`CMakeLists.txt`。
- 新建：`flutter_client/lib/src/services/windows_adapter_service.dart`。
- 修改：`flutter_client/lib/src/services/windows_wake_service.dart`、`flutter_client/lib/app.dart`、`flutter_client/lib/src/screens/wake_screen.dart`。
- 测试：新建 `flutter_client/test/windows_adapter_service_test.dart`；更新 `windows_wake_service_test.dart`、`wake_screen_test.dart`。

**接口**
```dart
enum AdapterScanState { detecting, failed, disconnected, absent, detected }
// WindowsAdapterService.scan() 返回结构化结果，不能以空列表吞掉异常。
Future<WindowsAdapterScan> scan();
// WindowsWakeService.adapters() 保留兼容，委托原生服务。
Future<List<WindowsWakeAdapter>> adapters();
```
`com.qsw.rdesk/windows_wake` MethodChannel 的 `listAdapters` 返回 `{schema:1, source:"ip_helper", elapsed_ms:int, adapters:[{id,name,mac,if_type,hardware,connected}]}`。调用失败抛 PlatformException，code 为 `adapter_query`，details 只含 API 名称、数值错误码、耗时。MAC 统一大写冒号格式；有效地址 6 字节、非全零、单播。

- [ ] 先写失败测试：原生错误不是 absent；无接口为 absent；以太网断开为 disconnected；中文网卡名称完整；USB 有线接受；Wi-Fi、VPN、虚拟交换接口不当作物理有线；多个有效网卡保留供用户选择。
- [ ] 在 `flutter_client` 运行 `flutter test test/windows_adapter_service_test.dart test/windows_wake_service_test.dart test/wake_screen_test.dart`，记录预期失败点。
- [ ] 用 `GetAdaptersAddresses` 获取接口，再以 `GetIfEntry2` 的 `HardwareInterface`、`Type`、`OperStatus` 分类。处理缓冲区大小变化，最多重试 3 次；单接口查询失败记录受限诊断，全部失败返回 failed，不能返回 absent。枚举在工作线程完成，结果回到 UI 线程，窗口销毁后不访问 messenger。
- [ ] 新建原生桥接源文件加入 runner CMake，链接 `iphlpapi.lib`；保持 PerMonitorV2。macOS/iOS/Android 不调用该通道。
- [ ] 页面独立处理扫描状态；检测失败提供“重试 / 复制诊断”，不提示检查 BIOS 或直接认定没插网线。辅助信息截断 MAC、移除完整机器名、IP 和凭据，复制前可预览。
- [ ] 跑上述测试至通过；本地 Windows VM 编译、启动并测试刷新/关闭竞争。记录 VM 的虚拟接口结果，不为了让 VM 显示成功而放宽物理网卡条件。
- [ ] 使用用户实际 Windows 新版本取得结构化诊断并验证物理网卡。如果远控输入无法操作，提供应用内复制入口；真实机器验证项保留未通过，不能用 VM 代替。
- [ ] 只提交本任务路径和精确改动段，提交说明：`fix: 修复 Windows 网卡检测误报并提供诊断`。

### Task 2：唤醒设置检测进程的编码和生命周期

**文件**：新建 `flutter_client/lib/src/services/windows_process_runner.dart`；修改 `windows_wake_service.dart`、`app.dart`；新建 `flutter_client/test/windows_process_runner_test.dart`。

**接口**：`Future<ProcessResult> runPowerShell(String script, {required Duration timeout})`。使用 `Process.start`、参数数组、UTF-8 字节解码，脚本以 UTF-16LE EncodedCommand 传入；不经过 cmd.exe。现有设备管理器和登录启动操作继续使用独立明确的方法。

- [ ] 写中文输出、UTF-8 BOM、非零退出、超时、取消及输出超过 64 KiB 测试，先运行确认失败。
- [ ] 显式设置 PowerShell OutputEncoding；收集 stdout/stderr 设置上限。15 秒超时或销毁时终止检测进程并等待退出，不只让 Future 超时；检测脚本不启动子进程。
- [ ] 驱动唤醒项目只读检测，未知/不支持分别显示；查询失败保留 Task 1 已识别网卡。诊断只暴露受控错误码和脱敏摘要，不直接打印命令/全部 stderr。
- [ ] 运行 `flutter test test/windows_process_runner_test.dart test/windows_wake_service_test.dart`，Windows VM 检查退出后无遗留 powershell 检测进程。
- [ ] 提交：`fix: 明确唤醒检测编码并清理超时进程`。

## 阶段 2：设备、导航、设置和字体

### Task 3：统一设备目录，保留历史与收藏

**文件**
- 新建：`flutter_client/lib/src/models/device_directory_entry.dart`、`lib/src/utils/device_directory.dart`、`test/device_directory_test.dart`。
- 修改：`lib/src/screens/my_devices_screen.dart`、`lib/src/providers/address_book_provider.dart`、`lib/src/models/address_book.dart`、`lib/src/models/connection_info.dart`、`lib/src/services/rdesk_bridge_service.dart`。

**接口**：`List<DeviceDirectoryEntry> mergeDeviceDirectory({required String endpointScope, required List<AccountDevice> accountDevices, required List<ConnectionRecord> history, required List<AddressBookEntry> saved, required List<WakeTarget> wakeTargets})`。目录条目保留各来源引用；合并键为规范化 HTTPS origin + deviceId，禁止凭名称或 MAC 合并。纯函数不写存储。

- [ ] 失败测试覆盖同设备多来源、同 ID 不同服务器、同名不同 ID、历史重复、登出、切换服务器、收藏别名优先、单独开机目标、旧数据缺少 endpoint。
- [ ] 为新历史/收藏写入可选 `endpointScope`，旧 JSON 可读。无范围旧条目保留“来源未记录”，不自动合并到当前账号；连接前沿用既有直连确认流程。首次升级不重写或丢弃旧条目。
- [ ] 目录状态优先使用当前服务器在线证据；历史成功不能推导当前在线。收藏来自地址簿，不把最近连接自动变收藏；保留分组编辑和别名。
- [ ] 设备页呈现“全部 / 在线 / 收藏”、搜索、添加、开机操作；刷新复用现有 Provider，不再每个来源各开轮询计时器。
- [ ] 跑 `flutter test test/device_directory_test.dart test/connection_history_dedupe_test.dart test/auth_session_recovery_test.dart`；手动确认旧收藏和历史仍可访问。
- [ ] 提交：`feat: 合并设备入口并保留来源与收藏数据`。

### Task 4：分平台导航、浅层设置与桌面文字

**文件**
- 新建：`lib/src/utils/platform_capabilities.dart`、`lib/src/widgets/settings_sections.dart`。
- 修改：`lib/src/widgets/main_shell.dart`、`lib/src/utils/router.dart`、`lib/src/utils/theme.dart`、`lib/src/screens/settings_screen.dart`、`profile_screen.dart`、`connection_settings_screen.dart`、`remote_assist_screen.dart`。
- 测试：新建 `test/platform_navigation_test.dart`、`test/settings_capabilities_test.dart`；维护 `test/review_truthfulness_test.dart`。

**接口**：`PlatformCapabilities.forPlatform(TargetPlatform platform)`，只由 OS 与真实实现能力决定 `isDesktop`、`canHost`、`canRelayWake`、`canScanPairing`、`canConfigureLocalWake`，窗口宽度仅控制展开/收起。

- [ ] 先写 Windows 640 宽仍为侧栏、iPhone/iPad 不出现 Windows 设置、Windows 无被控权限、Mac 有真实共享入口的测试；旧路由可重定向，不返回空页面。
- [ ] 桌面 shell 分支为设备、协助、开机、设置、账号；手机可见项为设备、协助、我的。保留 `/cloud`→设备、`/addressbook`→收藏、`/connection-settings`→设置网络的兼容路由。远控会话继续走 rootNavigator，不嵌入窄内容区。
- [ ] 设置数据与行为保持现有 Provider；提取可复用分组。桌面页内常规/安全/网络/关于；手机我的直达分组。删除重复入口，不删已有安全控制。版本从 package_info_plus 读取，不继续硬编码 2.1.0。
- [ ] Windows 字体 `Microsoft YaHei UI`，回退 `Segoe UI`、`Microsoft YaHei`；正文 16、说明 13、按钮 14、标题 24。主要字色浅色主题 #172033、辅助 #526074；深色使用对应高对比色。减少大渐变/大圆角，保持键盘焦点和语义标签。
- [ ] 跑 `flutter test test/platform_navigation_test.dart test/settings_capabilities_test.dart test/review_truthfulness_test.dart`。Widget 场景覆盖宽度 640/1024/1440、文本缩放 1/1.5/2；真实 Windows 显示缩放 100/125/150/200% 检查溢出与字体，不以远程视频清晰度作为唯一依据。
- [ ] 提交：`feat: 拆分桌面手机导航并简化设置与字体`。

## 阶段 3：安全配对协议与手机扫码

### Task 5：短时配对服务端协议

**文件**：新建 `crates/rdesk_server/src/wake/pairing.rs`、`pairing_tests.rs`；修改 `wake/mod.rs`、`model.rs`、`routes.rs`、`store.rs`。账号退出/删除若需挂钩，精确修改已脏 `src/main.rs` 中对应函数，不能混入捕获重构。

**固定协议**（全部使用现有 Bearer 账号认证；敏感证明在 POST JSON 中，禁止放 URL 查询和访问日志）

| 路由 | 输入 | 输出/行为 |
|---|---|---|
| POST `/api/wake/pairings` | name, device_id, mac | id, qr_proof, desktop_proof, manual_code, expires_at_ms；5 分钟有效 |
| POST `/api/wake/pairings/resolve` | id+qr_proof 或 manual_code，二者择一 | 同账号电脑摘要、会话状态；无永久令牌 |
| POST `/api/wake/pairings/:id/confirm` | qr_proof 或 manual_code | 原子确认手机认领，一次消费；状态 confirmed；不创建可开机目标 |
| POST `/api/wake/pairings/:id/status` | desktop_proof | pending/confirmed/claimed/expired；无账号秘密 |
| POST `/api/wake/pairings/:id/claim` | desktop_proof, enrollment_token | 创建 draft 目标并保存 token 哈希；返回 target_id，无明文 token |
| POST `/api/wake/pairings/:id/cancel` | desktop_proof | 取消未领取会话，后续领取失败 |
| POST `/api/wake/targets/:id/complete` | agent_id, bios_confirmed:true | 同账号助手、有效目标，更新配置完成标记 |

Windows 在 claim 前本地生成并安全存储 32 字节随机 `enrollment_token`（64 位十六进制），claim 只提交给已配置 HTTPS 服务；服务端仅持久化哈希。Windows 已持有自己的令牌，手机永远不参与其传递。相同 desktop_proof + token 重试返回同一个 target_id；换 token、重复手机 confirm 返回 conflict。

二维码是严格 JSON：`{"type":"rdesk-wake-pair","version":1,"id":"…","proof":"…"}`，没有 URL、服务器地址、账号密码或设备永久令牌。允许的字段和长度封闭校验。

- [ ] 先写协议集成失败测试：正常确认/领取/心跳；跨账号；未确认领取；过期边界；确认重放；并发确认只成功一次；相同领取重试；不同 token 重试；写盘失败不产生成功；删除账号/退出创建会话后不可继续。
- [ ] 内存 PairingRuntime 保存证明哈希、账号/创建会话绑定、状态和领取目标引用；全局最多 1000 条、每账号最多 3 个未完成、5 分钟过期清理。证明 256 位随机；manual_code 为无歧义大写 Base32 的 16 字符（80 位随机）。每账号 resolve/confirm 失败尝试最多 20 次/5 分钟、创建最多 6 次/5 分钟，超出 429。
- [ ] 用 `tokio::sync::Mutex` 串行保护状态转换，不跨 await 持有 std Mutex；统一锁顺序 pairing→user_store_write。磁盘原子写入成功后才变 claimed；存储失败保留可重试状态。删除/退出通过认证和存储锁内复查，防止认证后被删除仍创建目标。
- [ ] WakeTarget 添加 `setup_complete`，serde 默认 true 兼容已有目标；扫码新目标为 false、agent_id 为空。requestWake 服务端拒绝未完成配置；complete 要求同账号有效助手、BIOS 确认，不声称已经通过硬件实测。手机读取目标列表后可继续完成草稿，不依赖二维码一直有效。
- [ ] 服务重启清空未完成配对会话；已经持久化的目标保留。Windows 本地保存 candidateToken + pairingId + endpoint + account，claim 响应丢失重试；会话已失效时尝试用 candidateToken 对当前账号匹配目标做心跳验证，成功才恢复，失败要求重新配对。新配对不得静默覆盖旧绑定。
- [ ] 配对路由 BodyLimit 16 KiB；对旧服务 404 返回“服务器需更新扫码配对功能”，不能退回无认证绑定。所有响应、日志测试断言不存在电脑永久 token。
- [ ] 运行 `cargo test -p rdesk_server wake::pairing_tests`、`cargo test -p rdesk_server`、`cargo check --workspace`。补充现有目标/助手删除、撤销、轮换与草稿交互测试。
- [ ] 提交：`feat: 增加账号内一次性开机配对协议`。

### Task 6：客户端配对状态机与 Windows 二维码页

**文件**：新建 `lib/src/models/wake_pairing.dart`、`lib/src/providers/wake_pairing_provider.dart`、`lib/src/screens/windows_wake_screen.dart`；修改 `wake_api.dart`、`windows_wake_service.dart`、`wake_provider.dart`、`models/wake.dart`、`app.dart`、`router.dart`、`pubspec.yaml`、`pubspec.lock`；新建 `test/wake_pairing_test.dart`、`test/windows_wake_screen_test.dart`。

**接口**：WakeApi 新增 `createPairing`、`resolvePairing`、`confirmPairing`、`pairingStatus`、`claimPairing`、`cancelPairing`、`completeTarget`，请求/响应严格对应 Task 5。Provider 状态 `idle/checking/waiting/confirmed/claiming/paired/expired/failed`，每次账号/端点变化递增 generation。

- [ ] 失败测试覆盖生成二维码、过期、同账号确认、claim 响应丢失、安全存储失败、登出、换服务器、重复扫码、离开页面计时器停止，以及候选令牌不可出现在 QR/诊断中。
- [ ] Windows 页独立呈现本机检测、电脑名称、二维码、倒计时和手动码；二维码用固定 `qr_flutter: 4.1.0`。只有选定真实网卡、登录有效时可创建，成功配对后显示配置是否完成。
- [ ] 轮询 2 秒一次，无重入；退后台、过期、销毁即停，恢复时查服务端状态。渲染剩余时间不延长实际 TTL；网络重试不能创建新会话或换令牌。
- [ ] Windows 在 claim 前安全写入候选令牌；写失败不调用 claim。领取成功升级为既有账号+端点隔离的 enrollment 存储，复用现有心跳逻辑。登录启动保留明确开关和失败反馈，不暗中提权。
- [ ] `flutter test test/wake_pairing_test.dart test/windows_wake_screen_test.dart test/windows_wake_service_test.dart test/wake_screen_test.dart` 全部通过；本地 HTTP fixture 证明请求调用的是当前已配置服务，而不是二维码输入的地址。
- [ ] 提交：`feat: 增加 Windows 扫码配对与可靠凭据恢复`。

### Task 7：iPhone / Android 相机扫描与简洁配置页

**文件**：新建 `lib/src/screens/wake_pairing_scan_screen.dart`、`wake_pairing_confirm_screen.dart`、`wake_mobile_setup_screen.dart`；修改 `my_devices_screen.dart`、`wake_screen.dart`、`router.dart`、`pubspec.yaml`、`pubspec.lock`、`ios/Runner/Info.plist`、`ios/Podfile.lock`、`android/app/src/main/AndroidManifest.xml`；按 Flutter 实际生成结果更新插件注册文件。测试新建 `test/wake_pairing_scan_test.dart`、`wake_mobile_setup_test.dart`。

**扫描边界**：固定 `mobile_scanner: 7.2.0`（发布源码 podspec iOS12、Flutter>=3.29，兼容当前工程；最终以本地构建验收）。Android 使用 bundled 扫码依赖，避免依赖首次联网下载模型。默认不返回/存储相机图片，仅获取 QR 文本。

- [ ] 先用可注入扫码控制器测试：点击才请求权限、拒绝可输入手动码、仅 QR 格式、长文本/错误版本/URL 被拒、扫描回调去重、退出停止相机、切后台停止、恢复不重复提交。
- [ ] 手机设备页扫码直达；无登录先引导登录，不把证明写入日志、路由 query、分析事件。扫码显示电脑摘要后由用户确认添加；扫码本身不能直接消费绑定。
- [ ] 相机用途说明为“用于扫描电脑上的 RDesk 配对二维码，添加远程开机设备”；保留现有照片用途声明。桌面无扫码入口，不增加 Mac 相机授权或启动相机。
- [ ] 配置页三段：选择家中助手→BIOS 指引→测试。唯一在线助手预选但不自动提交，多台明确选；没有助手显示待配置与在家 Android 操作指引。助手离线保留原选择，不能静默换机器。
- [ ] 手机确认后等待电脑领取；中断时重新加载目标恢复草稿。完成配置调用 completeTarget，测试动作调用原有 requestWake；只收到 sent 显示“信号已发送”，只有心跳证据才显示“电脑已上线”。不自动触发电脑休眠/关机。
- [ ] `flutter test test/wake_pairing_scan_test.dart test/wake_mobile_setup_test.dart test/wake_pairing_test.dart test/review_truthfulness_test.dart`；本地 iOS 构建并安装到已连接 iPhone，实测系统权限、相机扫描 Windows 屏幕、返回桌面再进、拒绝权限手动码。
- [ ] Android 本地 APK 构建。连接到非审核专用设备时实测扫码及后台助手；不得为了测试破坏现有 App Review 演示手机的常驻被控状态。
- [ ] 提交：`feat: 支持 iPhone 和 Android 扫码添加开机电脑`。

## 阶段 4：整体验收与本地成品发布

### Task 8：回归、实机证据和兼容服务部署

**文件**：新建 `docs/validation/cross-platform-redesign-2026-09-20.md`；更新 `docs/local-release.md`、`deploy/privacy.html`、`deploy/support.html` 中本次真实能力与相机用途；若碰到审核文档仅记录拟同步内容，不覆盖其已有未提交修改。

- [ ] 检查所有新增测试和静态检查：`flutter analyze`、`flutter test`、`cargo check --workspace`、`cargo test -p rdesk_server`。记录原有提示与新增问题，不将已有失败默认为可忽略。
- [ ] 远控回归重点跑既有 auth_session_recovery、connection_history_dedupe、review_truthfulness、canvas_rotation、remote_canvas_pointer、session_view_only、remote_action_sheet、remote_key_action、remote_toolbar_controller、desktop_host_action；涉及现有 capture 改动的工作区结果与干净发行结果分别记录。
- [ ] 在干净发行源码中本地交叉编译服务端，检查 Linux 架构及动态库兼容；本地服务器跑完整配对→助手认领→sent→目标心跳 online 集成流程，加入旧客户端原有路径回归。
- [ ] 查 live DNS/nginx/service 确认实际 API 所在机，不能把网站主机等同 API 主机。当前已验证布局：API 在 101.37.21.147，网站文件在 124.223.200.182，经 qisw.top 入口转发；变更前重新核对。
- [ ] 部署前备份旧二进制、配置和用户数据；上传本地成品、核对 SHA256、原子替换、重启真实服务。健康检查和测试账号协议通过后才发布客户端；失败恢复旧二进制及必要数据快照，避免旧版本删除新字段。
- [ ] 实机矩阵逐项标注通过/失败/未覆盖：实际 Windows 网卡、四种显示缩放、iPhone 相机配对、Android 助手发包、睡眠、关机、蜂窝网络、隔夜。用户未在场的关机/隔夜项不自动执行、不虚报。
- [ ] 验收设备入口/收藏/搜索/账号/设置常用路径，检查 Windows 窄窗口与 iPhone 大字体；保存去掉凭据和二维码证明的截图。

### Task 9：安装包、官网和交付状态

**文件**：修改 `flutter_client/pubspec.yaml` 版本、`deploy/releases.json`、生成 `deploy/index.html`/`download.html`；更新上面的验证报告。

- [ ] 定版前读取当前商店与已有发行版本，选择未占用版本/build。保持 iOS Runner/Extension 同版本；只为本地安装也不伪称商店已发布。
- [ ] Windows 在现有本地 Windows 11 VM 执行 `scripts/build_windows.ps1`；验证 ZIP/安装 EXE、启动、中文字符、静默安装后文件一致。恢复 VM 原有电源状态。
- [ ] Android 本地 release APK 构建与签名校验；Mac 使用 `flutter_client/build_install.sh macos` Developer ID 安装流程及 `scripts/verify_macos_install.sh`；iPhone 用 `scripts/reinstall_ios.sh` 本地安装，不自动提交 App Store。
- [ ] 五类当前下载成品逐项核验真实版本、架构、签名/哈希；尚未更新的平台保持原有版本标记，禁止用新版本号包住旧文件。
- [ ] 用 `scripts/package_website.py` 本地组装预构建网站，上传自有网站机，保留旧 release 和可回滚 current 链接。核验 `/rdesk/`、全部新文件 HEAD/GET/Range、SHA256，检查其他网站路由未受影响。
- [ ] 提交仅本任务功能和发布文件；推送前确认 `.github/workflows` 没有自动云构建；按项目规则推送 `origin master`。AGENTS、凭据、诊断原文、临时构建目录不提交。
- [ ] 最终报告提供新下载链接、真实完成项、实机验收缺口和 iOS 本地/商店边界。新安装包发布不等于家中机器已经完成配置，也不等于隔夜可靠性已证明。

## 失败分类与对应验收

| 失败类别 | 必须通过的证据 |
|---|---|
| 依赖、原生桥接、运行环境 | Task 1/2 的原生错误、中文编码、超时退出；本地 Windows/iOS/Android 构建 |
| 生命周期与并发 | Task 5 的并发消费/写盘失败/claim 幂等；Task 6/7 的登出、切端点、后台、销毁 |
| 身份与数据完整性 | Task 3 的来源去重与旧数据保留；Task 5 的跨账号、重放、删除账号、日志无凭据 |
| 平台与可访问性 | Task 4 的桌面/手机路由、Windows 能力过滤、文本缩放和实机 DPI |
| 发布与真实硬件 | Task 8/9 的旧协议兼容、备份回滚、公开下载哈希；物理开机与隔夜独立记录 |

## 自审结论

- 用户确认的网卡、扫码、桌面/手机分离、字体、浅层设置均映射到独立任务，任务按依赖顺序执行。
- 配对协议明确手机确认与 Windows 领取的不同证明；设备令牌先在电脑安全存储再提交哈希登记，手机无法取得它。
- 新目标可保留待完成状态；硬件配置与上线证据没有被二维码扫描成功替代。
- 与已有脏文件相交的路径已点名，发行要求干净来源，不遗漏已有捕获/审核工作的保留要求。
- 真实 Windows 输入操作、家庭 Android 连接和隔夜测试仍是实机验收条件；自动测试不能代替这些结果。

## 已核验依赖依据

- qr_flutter 4.1.0：[官方 API](https://pub.dev/documentation/qr_flutter/latest/)。
- mobile_scanner 7.2.0：[发布源码 podspec](https://raw.githubusercontent.com/juliansteenbakker/mobile_scanner/v7.2.0/darwin/mobile_scanner.podspec)、[pubspec](https://raw.githubusercontent.com/juliansteenbakker/mobile_scanner/v7.2.0/pubspec.yaml)、[生命周期与授权说明](https://pub.dev/packages/mobile_scanner/versions/7.2.0)。
