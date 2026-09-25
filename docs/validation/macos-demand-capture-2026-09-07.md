# macOS 按需采集修复与本地验证

验证日期：2026-09-07。工作区 `/Users/qsw/work/project/rdesk`，安装位置 `/Applications/rdesk.app`。本次仅完成本地修改、构建、签名安装和验证，没有提交、推送或部署。原有 8 个修改文件的变更已核对保留，其中 5 个未触及文件的 diff 与工作开始时完全一致。

## 根因

1. `DesktopHostProvider.startHosting()` 将在线托管与 100 ms 截图轮询直接绑定；取帧后无条件尝试中继上传，没有观看需求门槛。修复前系统日志在 `rdesk[940]` 中持续出现 `SCShareableContent` 和 `RPDaemonProxy captureScreenshot` 调用，确认是实际采集。
2. 8 秒恢复任务在 `isRunning == false` 时重新调用 `startHosting()`，没有保存用户主动停止的意图。刷新与权限恢复也只检查这个混合状态。
3. LAN 令牌只表示鉴权，中继令牌可存活 30 分钟；原控制端断开只删除本地映射。两条路径都缺少独立的观看存活/结束信号。离开远程桌面进入文件管理时，画面订阅也未释放。
4. 原生截图、后台 JPEG 编码、CLI 超时回退及上传任务缺少统一失效边界，停止期间的异步结果仍可能返回。旧 CLI 还曾在系统临时目录留下 `rdesk_desktop_frame.jpg`。

## 修改文件与行为

| 文件 | 修改 |
|---|---|
| `flutter_client/lib/src/providers/desktop_host_provider.dart` | 分离托管意图、观看租约、采集状态；停止时先同步撤销意图、失效代次、取消计时器/上传并清空帧，再处理网络收尾；注册和心跳独立于截图。LAN 只有认证后的画面 GET 才续约。 |
| `flutter_client/lib/src/services/desktop_host_service.dart` | 独立采集启停与代次校验；不再通过 CLI 回退截图；迟到帧不交付，原生超时取消。 |
| `flutter_client/macos/Runner/MainFlutterWindow.swift` | 原生默认关闭采集；取消 Task、检查代次；停止后不再编码/返回旧截图；提供采集计数日志；清理旧 CLI 临时截图。保留工作区原有按键/Mission Control 修改。 |
| `flutter_client/lib/src/services/rdesk_bridge_service.dart` | 查询中继观看租约；上传连接独立取消及超时；通知观看结束/会话关闭；替换连接端点时释放旧令牌的观看租约。 |
| `flutter_client/lib/src/providers/session_provider.dart`、`flutter_client/lib/src/screens/remote_desktop_screen.dart` | 远程桌面可见时订阅画面；进入文件页/离开画面页后释放观看、保留认证；返回时恢复；异步重新绑定检查代次。 |
| `crates/rdesk_server/src/main.rs` | 新增观看租约查询、停止观看、关闭会话；HTTP 画面请求及 WebSocket 实际心跳续约；无观看或代次过期的按需上传返回 409；最后租约消失清理帧。保留旧移动主机上传方式和 WS 输入转发。 |
| `flutter_client/lib/src/screens/home_screen.dart`、`flutter_client/lib/src/screens/settings_screen.dart` | 区分“在线待命 · 未采集屏幕”和“正在共享屏幕”。 |
| 两个 `desktop_*` 新测试文件、`crates/rdesk_server/src/capture_tests.rs` | 生命周期、鉴权、迟到结果、上传取消、权限恢复、有限断线释放与兼容性回归。 |
| 本地 `AGENTS.md` | 将“持续轮询恢复权限”改为仅有有效观看需求时恢复，并记录协议和验收规则。继续保持本地忽略。 |

当前桌面没有独立的自动本地实时预览消费者。将来若加入本地预览，必须显式申请/释放采集需求，不能因页面展示而自动截图。

## 生命周期约定

- 观看租约为 10 秒；LAN 每 250 ms 检查到期，中继需求每秒查询，收到响应时扣除请求耗时。主机与中继断网不延长旧租约。异常释放上限约为最后一次证明存活后的 10 秒加一次 250 ms 检查间隔。
- 新客户端正常断开发送 `/session/close`；进入文件页发送 `/session/screen/stop`，后者保留认证。LAN 立即释放；中继主机在下一次需求查询获知停止，通常不超过约 1 秒。
- 中继 HTTP 取帧、WS 建立与收到 Pong 才续约；鉴权解析、待处理/拒绝的连接请求、文件/输入请求、设备心跳均不产生采集需求。WS 保持 TCP 但停止回应不会永久续约。
- Native 已提交给系统的单次截图可能仍完成系统收尾，但失效 Task 不再进入 JPEG 编码或交付。隐私指示灯是否有残留，须与原生计数、系统采集调用共同判断。
- 中继按需协议包含 `on_demand_capture`、`/api/preview/host/viewers`、`capture_epoch` 和观看关闭接口。旧服务器不能证明观看需求时，客户端保持不采集并提示升级中继，不退回持续截图。

## 自动验证

- 测试先行复现：修复前“只启动托管后取帧应为空”失败，实际拿到画面；修复前服务端接受无人观看的上传，预期 409，实际 200。修复后通过。
- 相关 Flutter 测试 **63 项通过**，包括新采集/需求测试及既有真实能力、旋转、仅观看输入限制、按键、操作面板、工具栏、账号恢复、连接历史测试。
- `cargo test -p rdesk_server`：**7 项通过**。
- `cargo check --workspace`：通过；保留既有 `file_list_responses` 未使用告警。
- `flutter analyze --no-pub`：无 error/warning；存在 **27 条既有 info 提示**，因此命令退出码为 1。未将其描述为分析器全绿。
- `git diff --check`：通过。使用 `build_install.sh macos` 完成 Release 构建、Developer ID 签名和安装；安装签名校验通过。

```sh
cd flutter_client
flutter --no-version-check test --no-pub \
  test/desktop_capture_lifecycle_test.dart test/desktop_host_demand_test.dart \
  test/review_truthfulness_test.dart test/canvas_rotation_test.dart \
  test/remote_canvas_pointer_test.dart test/session_view_only_test.dart \
  test/remote_action_sheet_test.dart test/remote_key_action_test.dart \
  test/remote_toolbar_controller_test.dart test/desktop_host_action_test.dart \
  test/auth_session_recovery_test.dart test/connection_history_dedupe_test.dart
```

## 安装版实际运行结果

| 场景 | 实际证据 |
|---|---|
| 启动、首页待命、仅鉴权及非画面请求 | 本机原生 requests/encoded 均为 0，uploadedFrames 为 0；设备监听和注册仍存在。 |
| LAN 授权观看 | 收到 11 张有效 JPEG；采集计数增长；中继上传始终为 0。 |
| LAN 停止、快速连接/断开 | 停止后缓存为空、采集 disabled/pending=false；3 轮重连正常。 |
| LAN 异常无请求 | 超过 10 秒后释放；再次请求可恢复。最终关闭后原生 requests 固定为 156、encoded 固定为 152；系统采集调用新增为 0。 |
| 本地 Rust 中继 HTTP | 鉴权后不请求画面时原生计数为 0；开始观看收到 16 张 JPEG，上传计数增长；停止后不再增长。 |
| 本地 Rust 中继 WebSocket | 收到 25 张 RDF1/JPEG 画面；正常关闭后释放；切到 HTTP 又收到 10 张 JPEG；3 轮 WS 重连正常。 |
| 无响应 WebSocket | 保持 TCP 但停止读取/回应 Ping，10 秒期限内自动释放；最终采集 disabled、pending=false、无帧缓存。 |
| 安装版手动停止 | 界面从“正在共享屏幕”变为“共享服务未启动”，观看端收到 401。等待 12 秒后监听仍停止，系统采集调用新增为 0；点击刷新也未重启。 |
| 安装版作为控制端 | 实际界面观看本地测试主机，远端已返回 183 帧时，本机采集、编码和上传均为 0。 |
| 进入文件页/返回 | 文件页期间远端请求计数保持 712，收到 screen stop 而未关闭认证；返回画面页后增至 1001，本机采集仍为 0。 |

最后一次原生缓存清理改动已重新构建、签名安装：启动后连续观察 10 秒，采集/编码/上传均为 0，系统新增采集调用为 0，旧 CLI 截图文件已不存在。

原服务器地址已恢复并读回核实，账号登录状态保留；本次添加的信任记录和连接历史已清理。本地中继、测试代理和画面测试主机均已停止。测试会话令牌临时文件已移除。

## 限制与未覆盖项

- **没有部署服务器。** 线上旧版中继尚未具备按需协议；当前修复在本地中继验证通过，线上中继连接需要之后单独部署配套服务端修改。LAN 可独立使用。
- 权限拒绝、恢复和停止期间迟到回调已用 MethodChannel 回归覆盖；未在本机实际撤销/重授 TCC 权限。
- 网络异常通过真实 WS 停止响应及中继失联测试模拟，未切断本机系统网络。
- 未安装/运行 iPhone、Android 真机新版本，未执行完整跨设备文件收发及全部键鼠动作；既有输入/仅观看/按键测试通过，文件页生命周期已在最终 macOS 安装版验证。
- 未对 macOS 隐私指示灯残留时长作保证；确认的是应用采集/编码/上传计数停止以及系统不再收到新的截图调用。
