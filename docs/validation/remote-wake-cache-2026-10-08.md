# 2026-10-08 远程开机助手缓存修复

## 现场与证据边界

- 用户三台设备登录同一账号；Android 已开启家中助手，Windows 已启用远程开机，关机前同时连接 Wi-Fi 和网线。iPhone 2.3.2（25）点击开机时提示「家中没有在线的开机助手」。
- 用户重新关闭、开启 Android 助手后才看到「运行中」，此前点击刷新未恢复。只读账号接口随后确认一台助手已启用且在线，最近有效轮询约 4.7 秒前；另一台旧助手已停用。没有连接的 Android adb 设备，未取得故障发生时的原生服务状态，不能断言最初停止轮询的具体原因。
- 两个同名 Windows 目标登记相同网卡但使用不同设备标识：旧目标绑定停用助手，新目标绑定当前在线助手。保留配置，没有自动删除或改写现场记录。
- 新目标的原版请求从 `sent` 变为 `online`；用户明确确认「是，远程点击后已开机」。这证明本次从关机状态实际远程开机成功，不代表隔夜、24/48 小时或不同硬件已通过验收。
- 上述实机成功发生在 Android 助手重新启用后；不能把它归因于随后完成的 iPhone 缓存修复。

## 可复现缺陷与修复

`WakeProvider.wake()` 原先只检查页面传入的目标和内存助手列表。目标快照仍为助手离线时，即使同一绑定助手已经恢复在线，也会因替代助手过滤排除原助手而误报没有在线助手；旧活动请求快照还可能阻止有效重试。

2.3.3（26）在每次开机动作中，通过当次冻结的账号、服务器作用域读取最新目标、所选目标的请求历史和助手列表。原绑定助手在线时直接使用，确实离线时才换用在线助手。查询失败显示实际错误；每次异步读取后检查账号 generation；本机重复点击和服务端活动请求去重继续生效。

新增六项回归覆盖助手恢复、目标与助手读取间状态变化、过期本地历史、服务端活动请求、查询错误和账号切换。先确认五项核心场景在旧实现上按预期失败，再应用最小修复。独立服务端协议复核未发现阻塞缺陷。

## 本地验证与 iPhone 安装

- `flutter analyze --no-pub`：无问题。
- `flutter test test/wake_api_test.dart test/wake_provider_test.dart test/wake_auth_lifecycle_test.dart test/wake_simple_flow_test.dart test/windows_wake_service_test.dart test/review_truthfulness_test.dart --no-pub --reporter expanded`：34 项全部通过。
- `flutter build ios --release`：本机 Xcode 构建成功，约 20.1 MB。
- `codesign --verify --deep --strict`：通过；主应用和 Broadcast Extension 均为 2.3.3（26），开发描述文件有效且包含目标 iPhone。
- 安装至物理 iPhone 17 Pro Max；设备回读应用「随控」、`com.qsw.rdesk`、2.3.3、构建 26；`devicectl` 启动成功。
- 主应用可执行文件 SHA-256：`302a152fafadca0cd2fcb297e00166168b8483f9f13f6bd9c2702077ed9d6f0e`。
- 本轮仅本地构建和手机安装；没有上传 App Store、更新官网安装包或部署服务端。仓库无 GitHub workflow 文件，不会因本次推送触发云端构建。

诊断输出只保留状态、时间差和匿名关联；临时读取的手机配置已删除，未把账号令牌、密码、MAC、IP 或助手名称写入日志和本记录。
