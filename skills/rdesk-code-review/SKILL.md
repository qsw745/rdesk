---
name: rdesk-code-review
description: 审查 rdesk 项目当前实现风险的项目内技能文件，包含本次代码审查结论、证据位置和后续复查清单。
---

# RDesk Code Review

## Scope

- 审查范围：`crates/`、`proto/`、`flutter_client/lib/`
- 校验命令：`cargo check --workspace`
- 校验命令：`flutter analyze`

## Validation Snapshot

- `cargo check --workspace` 通过；存在若干 unused/dead-code 警告，和核心模块仍为 stub 的现状一致。
- `flutter analyze` 返回 30 个 `info` 和 1 个 `warning`；目前没有阻塞性编译错误，但存在多处实现/交互风险未被静态检查覆盖。

## Second Review

审查基线：`9749903 Harden preview auth and fail unimplemented core startup`

### Fixed In This Revision

- `/api/file/download/:file_id` 已增加 viewer token 校验。
- Rust core 的 `RemoteClient::connect()` / `RemoteServer::start()` 不再返回假的成功态，而是显式失败。
- 远程文件下载不再伪造完成态，而是显式抛出未实现错误。
- 永久密码和已信任设备密码已迁移到 `flutter_secure_storage`。

### Remaining Findings

1. `register_preview` 仍然可以通过“省略 `host_token`”旁路续租校验，攻击者既能覆盖主机注册信息，也能直接拿到真实 `host_token`。
   - 证据：`crates/rdesk_server/src/main.rs:662`
   - 说明：当 `device_id` 已存在时，代码只在“提供了非空 `host_token` 且不匹配”时拒绝请求；如果攻击者直接不传或传空字符串，请求会被接受，并且响应体里会返回现有条目的 `host_token`。这比上个版本更严重，因为旁路后不仅能改访问控制，还能窃取 host token。
   - 建议：已有注册项时必须要求 `host_token` 存在且匹配；不要在未认证请求里回显现有 `host_token`。

2. LAN session token 在断开 viewer、停止 hosting、重建 LAN relay 时都没有失效，旧 viewer 仍可继续访问新开的本地控制面。
   - 证据：`flutter_client/lib/src/providers/desktop_host_provider.dart:52`
   - 证据：`flutter_client/lib/src/providers/desktop_host_provider.dart:406`
   - 证据：`flutter_client/lib/src/providers/desktop_host_provider.dart:599`
   - 证据：`flutter_client/lib/src/providers/android_host_provider.dart:47`
   - 证据：`flutter_client/lib/src/providers/android_host_provider.dart:397`
   - 证据：`flutter_client/lib/src/providers/android_host_provider.dart:603`
   - 说明：token 被保存在 provider 级别的 `_lanSessionTokens` 集合里，但 `_closeLanRelay()` 只关闭 `HttpServer`，没有清空 token。`disconnectCurrentViewer()` 和 stop/start 只是重启 relay，不会吊销旧 token，因此之前连接过的 viewer 仍可直接复用旧 token。
   - 建议：在 `_closeLanRelay()`、`disconnectCurrentViewer()`、`stopHosting()` 中统一清空 token；最好把 token 和单个会话绑定并支持轮换。

3. `connectDirectIp()` 现在不会把密码传给 `/session/trust`，因此拿不到 LAN session token；随后所有受保护接口都会返回 401，但客户端仍把直连会话记为成功。
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:248`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:297`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:1907`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:1479`
   - 说明：这次修复把 LAN relay 改成 token 保护是对的，但 `connectDirectIp()` 仍然只做 `/health` 探测，然后调用 `_trustViewerOnRemote()` 时没有传 `password`。由于 host 侧会对 `/session/trust` 做密码校验，客户端通常拿不到 `session_token`，之后访问 `/frame.jpg`、`/input/*` 时会被拒绝，形成“连接成功但全链路不可用”的回归。
   - 建议：直连流程必须显式接收并传递访问密码，在 `/session/trust` 成功换到 `session_token` 之前不要返回成功 session。

4. 远程目录读取现在会抛异常，但调用链没有兜底，`FileManagerScreen` 初始化时会触发未处理的异步错误。
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:956`
   - 证据：`flutter_client/lib/src/providers/file_transfer_provider.dart:40`
   - 证据：`flutter_client/lib/src/screens/file_manager_screen.dart:29`
   - 说明：上次把“失败后回退到本地目录”的逻辑改掉是正确方向，但 `loadRemoteDir()` 仍然直接向外抛异常，而页面 `initState()` 里是裸调用，没有 `await`、没有 `catchError`、也没有 provider 级错误状态。这会把原来的错误 UI 退化成未处理异常。
   - 建议：把远程列表错误收敛到 provider 状态里，再由页面渲染错误提示或重试入口。

## Findings

### Critical

1. Preview 注册和注销接口缺少主机身份校验，任意调用方都可以覆盖或删除目标设备的在线注册信息。
   - 证据：`crates/rdesk_server/src/main.rs:658`
   - 证据：`crates/rdesk_server/src/main.rs:705`
   - 说明：`register_preview` 直接以 `device_id` 为键覆盖 `password_hash`、`auto_accept`、`trusted_viewers` 等访问控制字段，并沿用已有 `host_token`；`unregister_preview` 甚至完全不校验 `host_token`。这意味着只要知道设备 ID，就可以发起 DoS，或者篡改真实主机的访问策略。
   - 建议：为注册续租和注销统一要求 `host_token` 或等价签名；首次注册与续租分离；对 `device_id` 的所有权建立显式绑定。

2. 直连 LAN/Tailscale 模式暴露了无鉴权的屏幕、输入、剪贴板和信任写入接口，网络内任意主机都可以直接控制被控端。
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:243`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:1397`
   - 证据：`flutter_client/lib/src/providers/desktop_host_provider.dart:350`
   - 证据：`flutter_client/lib/src/providers/android_host_provider.dart:333`
   - 说明：`connectDirectIp()` 只探测 `/health`，随后把 `/frame.jpg` 作为会话入口保存，控制请求通过 `_resolveControlUri()` 直接替换路径发送；而桌面端和 Android 端的本地 HTTP relay 对 `/frame.jpg`、`/input/*`、`/clipboard/*`、`/session/trust`、`/settings/quality` 都没有任何 token 或密码校验。
   - 建议：为直连模式补齐握手和会话 token；至少要求一次带密码的授权换取短期 token，所有控制和媒体接口都校验该 token。

### Warning

3. 文件下载接口没有任何鉴权，拿到 `file_id` 就能从服务端直接取回上传内容。
   - 证据：`crates/rdesk_server/src/main.rs:1415`
   - 说明：`file_download()` 只根据路径参数里的 `file_id` 读取 `file_store` 并返回二进制，不校验 viewer token、host token 或账号会话。当前 `file_id` 虽然是随机值，但它已经被当作唯一授权因子使用，一旦泄露即可以被任意方复用直到 TTL 过期。
   - 建议：把下载接口和 viewer/host 会话绑定，或者给文件下载签发一次性短期令牌。

4. Rust 核心连接栈和 Flutter bridge 仍是占位实现，但当前 API 会返回“连接成功/开始监听”的成功态，容易误导调用方和测试结果。
   - 证据：`crates/rdesk_core/src/client.rs:43`
   - 证据：`crates/rdesk_core/src/server.rs:42`
   - 证据：`flutter_client/lib/main.dart:16`
   - 说明：`RemoteClient::connect()` 没有做 rendezvous、QUIC、Noise 或鉴权就直接创建本地 session 并 `activate()`；`RemoteServer::start()/accept_connection()` 同样没有真实网络监听却返回成功；Flutter 启动入口也还没初始化 `flutter_rust_bridge`。如果后续调用方切换到这些接口，会得到“功能可用”的假象。
   - 建议：在真正接通链路前不要暴露成功态；未实现路径应显式返回错误；桥接初始化要和实际调用链同步落地。

5. 文件管理的下载链路和失败回退会制造“传输成功”的假象，存在误导用户和误操作本地文件系统的风险。
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:954`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:1041`
   - 证据：`flutter_client/lib/src/providers/file_transfer_provider.dart:96`
   - 说明：`listRemoteDirectory()` 在任何异常下都会回退到 `listLocalDirectory(path)`，远程面板可能直接展示本地目录内容；`downloadFile()` 仍是 400ms 的占位延迟，但 `FileTransferProvider` 会先模拟进度并把任务推进到 completed。用户会看到“远程下载成功”，实际上没有落盘。
   - 建议：远程列表失败时返回错误态而不是本地目录；未实现的下载能力应在 UI 上明确禁用或标注为未完成。

6. 永久密码和已信任设备密码以明文形式保存在 `SharedPreferences`，本地设备失陷后可直接复用。
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:602`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:617`
   - 证据：`flutter_client/lib/src/services/rdesk_bridge_service.dart:747`
   - 说明：信任列表里直接保存 `password` 字段，永久密码也直接写入 `_permanentPasswordKey`。这和 README 中强调的安全定位不一致，而且没有结合平台密钥链/加密存储。
   - 建议：改用平台安全存储；若必须缓存可复用凭据，至少加设备绑定和本地加密。

## Re-Review Checklist

- 先复查所有 `device_id` 相关接口是否已经统一引入主机身份校验。
- 复查直连模式是否已经建立一次性的会话 token，并覆盖 `/frame.jpg`、`/input/*`、`/clipboard/*`、`/session/trust` 等接口。
- 复查文件传输是否已具备真实下载实现，以及失败时 UI 是否仍会显示完成态。
- 复查 Rust core 和 Flutter 启动链路是否还存在“stub 但返回成功”的接口。
