# Windows 远程开机实施计划

> 执行者：按任务使用 `superpowers:executing-plans`，或在用户选择逐任务委派后使用 `superpowers:subagent-driven-development`。本文等待用户审阅并选择执行方式，尚未开始产品实现。复选框用于记录实际完成情况。

**目标：** 手机及电脑通过家中安卓助手，在外网唤醒已配置的 Windows 有线网卡目标，并提供可区分链路阶段的隔夜诊断。

**架构：** Flutter 提供账号内的目标配置、助手管理和请求状态；Rust 负责持久配置、权限及短期任务；独立 Android 原生前台服务接收任务并发送局域网 WOL 广播。Windows 只负责网卡选择、目标注册和应用在线心跳，本次不补充 Windows 远控。

**技术栈：** 现有 Flutter/Dart、Provider、GoRouter、Dart HttpClient、FlutterSecureStorage；Rust Tokio/Axum/Serde；Kotlin、Android Service、HttpsURLConnection、DatagramSocket、Android Keystore。不引入推送平台、路由器插件或新数据库。

**设计：** [已确认设计](../specs/2026-09-19-remote-wake-design.md)。执行前同时读取设计与本计划。

## 全局约束

- Windows 通过网线连接小米 AX3000；安卓在同一家庭 LAN 内。安卓型号和供电情况在实机配置时核实，不阻塞通用实现。
- 服务端长轮询 5 秒、客户端读取超时 12 秒、助手在线租约 30 秒、请求可领取期 30 秒、观察 Windows 上线 120 秒。
- WOL 为 102 字节、UDP 9：6 字节 `FF` + 16 次目标单播 MAC。每个请求一个批次、3 包、间隔 200 毫秒。
- 每账号最多保留最近 50 次请求诊断、最长 7 天；账号删除清除配置、凭据和诊断。
- 请求已提交、信号已发送、等待上线、已上线、未确认上线必须分别呈现。
- 独立 Android `connectedDevice` 前台服务；不开录屏、不依赖无障碍、不点亮屏幕、不自动修改系统电源或 BIOS。
- 首版不承诺安卓强行停止/重启后的自动恢复，不安装 Windows 管理员服务或登录前计划任务。
- 唤醒凭据只能通过 HTTPS 请求头传输。开发测试允许显式注入 loopback HTTP 地址，发布构建不接受任意 HTTP。
- 保留当前 `master` 工作区全部已有修改；只提交本功能文件和修改片段，不提交本地 `AGENTS.md`。
- 功能验证通过后按项目要求打包/安装可用设备、提交并推送 `origin master`；服务端部署另行确认。
- 真实隔夜/24 小时/48 小时验证未完成时必须标记未覆盖，不能把单元测试当成长时间真实开机成功。

## 审查重点

1. 用户停止助手后，迟到的长轮询响应不得发包或重启服务；任务 4、6 用受控延迟响应验证。
2. 服务端重启不能把历史请求重新发出；任务 1、2 验证恢复时终止在途任务，助手租约从离线开始。
3. A 账号退出后登录 B 账号，旧助手凭据、目标及回执不能进入新账号；任务 3、6 验证隔离及 generation 失效。
4. 关机后旧 IP/ARP 消失，不应影响向指定 MAC 的广播；任务 4 验证报文不使用目标 IP，任务 8 做隔夜实测。
5. Windows 到达登录界面但应用未运行，界面只能说未确认上线；任务 2、7 分别覆盖状态机与文案。

## 文件边界

| 范围 | 新增文件 | 现有接入位置 |
| --- | --- | --- |
| Rust | `crates/rdesk_server/src/wake/{mod,model,store,routes,tests}.rs` | `main.rs` 的 `UserRecord`、`AppState`、账号持久化及路由 |
| Flutter 协议 | `lib/src/models/wake.dart`、`lib/src/services/wake_api.dart` | `rdesk_bridge_service.dart` 增加规范化 API 地址只读接口 |
| Flutter 生命周期 | `lib/src/services/wake_agent_channel.dart`、`lib/src/providers/wake_provider.dart` | `app.dart`、`auth_provider.dart` |
| Windows | `lib/src/services/windows_wake_service.dart` | 新开机设置页，由 Provider 启停心跳 |
| Android | `wake/WakePacket.kt`、`WakeRelayEngine.kt`、`WakeRelayService.kt`、`WakeRelayStore.kt`、`WakeRelayPlugin.kt`、`WakeNetwork.kt` | `MainActivity.kt`、Manifest、Gradle 单元测试依赖 |
| 界面 | `lib/src/screens/{wake_screen,wake_setup_screen}.dart`、`lib/src/widgets/wake_request_status.dart` | `utils/router.dart`、设备页和设置页 |
| 验证及说明 | `flutter_client/test/wake_*_test.dart`、Android `wake/*Test.kt`、`docs/remote-wake.md`、`docs/validation/remote-wake.md` | 公开隐私/支持/下载说明及审核真实性回归 |

表中的 `lib` 均属于 `flutter_client`；Android Kotlin 源码根为 `flutter_client/android/app/src/main/kotlin/com/qsw/rdesk`，测试根为对应 `src/test/kotlin/com/qsw/rdesk`。不移动现有远控/采集模块。

## 协议约定

所有时间字段为服务端 Unix 毫秒。时间差执行使用 Android `elapsedRealtime`，客户端墙钟不得决定任务是否过期。所有列表返回 `server_time_ms`。

持久对象：

```text
WakeTarget { id, owner_id, name, device_id, mac, agent_id, revision,
             target_token_hash, created_at_ms }
WakeAgent  { id, owner_id, name, agent_token_hash, revision, enabled }
WakeRequest { id, owner_id, target_id, agent_id, target_revision,
              created_at_ms, expires_at_ms, observe_until_ms, phase,
              claimed_at_ms?, sent_at_ms?, online_at_ms?, error_code? }
phase = queued | claimed | sent | online | unconfirmed | expired |
        failed | cancelled | interrupted
```

`owner_id`、凭据摘要不返回客户端。原始凭据只在创建/轮换时返回一次。目标上线时间及助手心跳属于内存租约，不从磁盘恢复成在线。MAC 统一保存为大写冒号分隔格式。

| 方法和路径 | 认证 | 行为 |
| --- | --- | --- |
| `GET /api/wake/targets` | 账号 Bearer | 本账号持久目标和派生在线状态 |
| `POST /api/wake/targets` | 账号 Bearer | 当前 Windows 首次配置，返回目标 ID 与专用心跳 token |
| `PUT /api/wake/targets/:id` | 账号 Bearer | 更新名称/MAC/助手，递增 revision、取消旧配置任务 |
| `DELETE /api/wake/targets/:id` | 账号 Bearer | 删除配置、吊销心跳 token、取消任务 |
| `POST /api/wake/targets/:id/rotate-token` | 账号 Bearer | 本机重新配置时轮换心跳 token |
| `POST /api/wake/targets/:id/heartbeat` | 目标 Bearer | 更新对应目标上线时间 |
| `GET /api/wake/agents` | 账号 Bearer | 本账号助手、启用状态及新鲜心跳 |
| `POST /api/wake/agents` | 账号 Bearer | 明确启用时创建助手及受限 token |
| `DELETE /api/wake/agents/:id` | 账号 Bearer | 吊销助手 token，保留目标但标记需重新选择助手 |
| `POST /api/wake/agents/:id/disable` | 助手 Bearer | 通知栏停止时自我吊销；不可吊销其他助手 |
| `POST /api/wake/agents/:id/poll` | 助手 Bearer | 刷新租约、最多等 5 秒；200 返回一项，204 表示无任务 |
| `POST /api/wake/requests` | 账号 Bearer | body 只有 `target_id`；在线助手才可创建，活动请求合并 |
| `GET /api/wake/requests?target_id=...` | 账号 Bearer | 有界诊断列表，检查目标归属 |
| `GET /api/wake/requests/:id` | 账号 Bearer | 单请求最新状态及各阶段时间 |
| `POST /api/wake/requests/:id/authorize-send` | 助手 Bearer | 发包前重验绑定/revision/有效期/吊销，返回一次短许可 |
| `POST /api/wake/requests/:id/result` | 助手 Bearer | 本助手的幂等回执；只接受 `sent` 或 `failed` |

错误格式：`{"code":"agent_offline","message":"开机助手离线"}`。状态码：400 参数不合法；401 凭据失效；404 不存在或不属于调用者；409 助手离线/目标在线/配置已变；410 请求过期；429 超限；503 不能持久化。旧服务端 404 显示“服务器暂不支持远程开机”，不能静默降级到录屏指令。

账号资源默认上限：20 个目标、5 个助手。每目标活动观察窗口内合并请求；终态之后 30 秒内不接受新的发送批次；每账号每分钟最多创建 10 个新请求，重复查询及幂等复用不计为新请求。

任务 1：持久配置、状态机与删除一致性
------------------------------------

**文件：** 新增 `wake/model.rs`、`wake/store.rs`、`wake/mod.rs`、`wake/tests.rs`；修改 `main.rs` 的 `UserRecord`、`register_account`、`delete_account`、`persist_users`。

**接口：**

```rust
// model.rs
pub(super) struct MacAddress(pub [u8; 6]);
impl MacAddress { pub fn parse(raw: &str) -> Result<Self, WakeError>; }
pub(super) enum WakeError { InvalidMac, NotFound, Unauthorized, AgentOffline,
    TargetOnline, Conflict, Expired, RateLimited, Storage }
pub(super) enum WakePhase { Queued, Claimed, Sent, Online, Unconfirmed,
    Expired, Failed, Cancelled, Interrupted }
// WakeTarget/WakeAgent/WakeRequest 字段按“协议约定”，derive Clone/Serialize/Deserialize。
#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
pub(super) struct WakeAccountData {
    pub targets: Vec<WakeTarget>,
    pub agents: Vec<WakeAgent>,
    pub requests: Vec<WakeRequest>,
}
impl WakeAccountData {
    pub fn prune(&mut self, now_ms: u64);
    pub fn recover_after_restart(&mut self, now_ms: u64);
}
// store.rs；Mutation 闭包同步执行，不跨 await 保存 DashMap guard。
pub(super) async fn update_wake<T>(state: &AppState, user_id: &str,
    mutation: impl FnOnce(&mut WakeAccountData) -> Result<T, WakeError>)
    -> Result<T, WakeError>;
```

- [ ] 开始任何代码修改前保存既有差异清单及二进制补丁到仓库外的唯一临时目录，保留路径到验证记录，不改动原工作区：

```bash
task_baseline_dir=$(mktemp -d /tmp/rdesk-wake-baseline.XXXXXX)
git status --porcelain=v1 > "$task_baseline_dir/status.txt"
git diff --binary > "$task_baseline_dir/working.patch"
git diff --cached --binary > "$task_baseline_dir/index.patch"
```

- [ ] 先写 MAC 测试，覆盖标准/短横线输入规范化，以及零地址、组播、广播、非法字符、错误长度拒绝。示例：

```rust
#[test]
fn rejects_multicast_and_accepts_normal_mac() {
    assert!(MacAddress::parse("01:00:5E:00:00:01").is_err());
    assert!(MacAddress::parse("FF:FF:FF:FF:FF:FF").is_err());
    assert!(MacAddress::parse("00:00:00:00:00:00").is_err());
    assert_eq!(MacAddress::parse("02-11-22-33-44-55").unwrap().0,
               [2, 17, 34, 51, 68, 85]);
}
```

- [ ] 运行 `cargo test -p rdesk_server wake::tests`，确认新增行为在实现前失败。
- [ ] 给 `UserRecord` 增加 `#[serde(default)] wake: WakeAccountData`。沿用当前 `Vec<UserRecord>` JSON，旧文件缺字段时正常加载。每账号 wake 配置、token 摘要和诊断与账号同文件原子保存，避免删除账号与删除第二份文件之间的部分提交。
- [ ] 提取原子快照写入函数，写临时文件、flush/sync、同目录 rename 后才发布内存态。注册/删除账号和 wake 修改持有同一 `user_store_write` 锁，重新检查账号状态，基于最新 snapshot 修改。不能持锁再调用旧的会重复加锁的 `persist_users`。

```rust
let _guard = state.user_store_write.lock().await;
let mut snapshot: Vec<UserRecord> = state.users.iter()
    .map(|entry| entry.value().clone()).collect();
let user = snapshot.iter_mut().find(|u| u.user_id == user_id)
    .ok_or(WakeError::NotFound)?;
let value = mutation(&mut user.wake)?;
let updated = user.clone();
// write_user_snapshot 定义为 store 内的 async fn，接收 &AppState、&[UserRecord]。
write_user_snapshot(state, &snapshot).await.map_err(|_| WakeError::Storage)?;
state.users.insert(user_id.to_owned(), updated);
Ok(value)
```

- [ ] 为写入失败、旧格式加载、并发修改不丢失、删除失败仍能登录及取回配置增加真实临时目录测试。临时路径使用 `std::env::temp_dir().join(Uuid::new_v4().to_string())`，测试结束只删除该目录。
- [ ] `prune` 同时按 7 天及 50 条限额裁剪，不保留已删除目标的 token；重启将所有非终态任务变为 `interrupted` 并清空在线租约。重启中断状态落盘失败时唤醒服务不启动。
- [ ] 运行本任务测试及 `cargo check --workspace`；检查 Git 仅暂存本任务片段，提交 `feat(wake): 保存开机配置与有界诊断`，不夹带已有采集修改。

任务 2：鉴权路由、领取回执与上线判定
----------------------------------

**文件：** `wake/routes.rs`、`wake/mod.rs`、`wake/tests.rs`；`main.rs` 接入 `wake::routes()` 和运行态。

**接口：** `pub(super) fn routes() -> Router<AppState>`；`WakeRuntime` 管理 `agent_seen`、`target_seen`、单账号速率窗口和助手 notify；运行态由 `AppState` 持有 `Arc<WakeRuntime>`。请求状态存入任务 1 的 `WakeAccountData`。

- [ ] 写路由集成测试，使用真实 loopback Axum 服务和临时账号，校验 A 的 token 访问 B 的 target/request/agent 一律失败；token 只能用于对应角色。测试夹具定义在 `wake/tests.rs` 的 `WakeFixture`：包含 `state`、两账号 ID、两账号 HeaderMap、临时目录，`new().await` 创建并清理目录。
- [ ] 先跑 `cargo test -p rdesk_server wake::tests` 确认缺失路由/状态检查导致失败，再实现表中的完整接口。
- [ ] token 使用现有 UUID 随机生成方式；存储以现有 `hash_password`/`verify_password` 处理，凭据没有用户密码复用。查找助手/目标使用 ID，禁止遍历校验所有 hash。HTTP body 限制 16 KiB，名称最多 80 字符，ID 和 MAC 严格解析。
- [ ] 用注入的 `now_ms` 做纯状态测试，不真的等待 120 秒。仅收到目标专用 token 的新鲜心跳可将请求从 `sent` 更新为 `online`；创建请求前在线的目标返回 `target_online`。如果心跳先于发送回执到达，回执时再次检查本请求创建后的心跳。

```rust
// model.rs
pub fn observed_online(created: u64, sent: Option<u64>, heartbeat: Option<u64>,
                       now: u64) -> bool {
    sent.is_some() && heartbeat.is_some_and(|seen|
        seen > created && seen <= now && now - seen < 30_000)
}
#[test]
fn no_app_heartbeat_never_means_online() {
    assert!(!observed_online(1_000, Some(2_000), None, 121_000));
    assert!(!observed_online(1_000, Some(2_000), Some(900), 3_000));
    assert!(observed_online(1_000, Some(2_000), Some(2_100), 3_000));
}
```

- [ ] 领取必须先持久标记 `claimed` 再交付，返回 `remaining_ms`、MAC、target revision、server time；丢包允许同一助手在期限内重领同请求，不能给另一助手。`authorize-send` 重验授权后提供最多 2 秒且不越过请求有效期的发送许可，发送前须在安卓单调时钟期限内执行。
- [ ] 重复回执只返回已保存结果，不能从 failed/cancelled/expired 变回 sent。撤销接口取消未发送任务；授权已发出之后的极短在途窗口无法跨网络物理撤回，文档如实说明，不声称绝对原子撤销。
- [ ] 每次 poll 刷新助手租约，204 空响应正常；错误重试不改变停止意图。轮询注册等待前后都检查队列，避免丢失通知；五秒后返回，不长时间持有持久化锁。
- [ ] 覆盖双客户端同时点击只产生一个请求、过期不能发送、撤销与在途回执、配置 revision 不匹配、重启不重发、50 条/7 天清理、30 秒冷却及账号速率限制。
- [ ] 运行 `cargo test -p rdesk_server` 和 `cargo check --workspace`；提交本任务片段 `feat(wake): 增加受控开机请求与状态接口`。

任务 3：Flutter 协议模型与隔离的 HTTP 客户端
------------------------------------------

**文件：** `flutter_client/lib/src/models/wake.dart`、`services/wake_api.dart`、`test/wake_api_test.dart`；bridge 增加 API 地址 getter。

**接口：** 所有 Dart 模型用不可变字段及 `fromJson`；snake_case JSON 对应 camelCase Dart。`WakeRequest.phase` 使用 `WakePhase` 枚举，未知服务端状态解析成 `unknown` 并禁止显示成功。

```dart
class WakeApi {
  WakeApi({required Future<Uri> Function() baseUri,
    required Future<String?> Function() accountToken, HttpClient? client});
  Future<List<WakeTarget>> targets();
  Future<List<WakeAgent>> agents();
  Future<WakeEnrollment> createAgent(String name);
  Future<WakeEnrollment> createTarget({required String name,
    required String deviceId, required String mac, required String agentId});
  Future<void> updateTarget(String id, {required String name,
    required String mac, required String agentId});
  Future<void> deleteTarget(String id);
  Future<WakeEnrollment> rotateTargetToken(String id);
  Future<void> revokeAgent(String id);
  Future<WakeRequest> requestWake(String targetId);
  Future<WakeRequest> request(String id);
  Future<List<WakeRequest>> history(String targetId);
  Future<void> targetHeartbeat(String id, String token);
  void close();
}
// WakeEnrollment：String id、String token；token 不进入 toString。
// WakeApiException：String code、String message、int statusCode。
```

- [ ] 用本地 `HttpServer` 写真实 HTTP 测试：每个请求重新取 token、Bearer 不出现在 URI、body JSON 正确、旧服务端 404、响应为空/错误格式/超时。参考现有 `auth_session_recovery_test.dart` 的 HttpOverrides，不测试源代码字符串。
- [ ] 运行 `flutter test test/wake_api_test.dart`，验证失败后实现接口。bridge 提供 `Future<Uri> getApiBaseUri()`，复用当前服务器迁移/规范化规则，不复制一套地址配置。
- [ ] 禁用自动跨源重定向，所有非 2xx 映射结构化错误，401 不偷偷重试带旧凭据的写请求。读取响应体上限 256 KiB，12 秒 timeout，释放连接。

```dart
final request = await client.openUrl(method, uri);
request.followRedirects = false;
request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
request.headers.contentType = ContentType.json;
// 每个响应先有界读取并耗尽或关闭；不把错误 body 或 token 放入日志。
```

- [ ] 模型测试将 `phase=sent` 断言为 `WakePhase.sent`，缺字段或未知状态不映射 `online`；列表独立于临时 account presence。
- [ ] 跑 API/模型测试和 `flutter analyze`，提交 `feat(wake): 增加跨端开机接口模型`。

任务 4：安卓 WOL 发送与可取消的原生助手
------------------------------------

**文件：** Android `wake/` 六个新文件；`MainActivity.kt`、`AndroidManifest.xml`、`build.gradle.kts`；新建对应测试。

**接口：**

```kotlin
object WakePacket { fun encode(mac: String): ByteArray }
data class WakeJob(val id: String, val targetId: String, val mac: String,
    val revision: Long, val remainingMs: Long)
data class SendPermit(val remainingMs: Long)
interface WakeTransport {
    fun poll(): WakeJob?
    fun authorize(job: WakeJob): SendPermit
    fun result(job: WakeJob, sent: Boolean, errorCode: String?)
    fun disable()
    fun cancel()
}
interface WakeSender { fun send(packet: ByteArray) }
interface WakeClock { fun elapsedMs(): Long; fun waitMs(ms: Long) }
interface WakeJournal { fun reserve(id: String): Boolean; fun clear() }
class WakeRelayEngine(val transport: WakeTransport, val sender: WakeSender,
    val clock: WakeClock, val journal: WakeJournal) {
    fun run(generation: Long)
    fun stop()
}
```

- [ ] 为包格式写 JUnit 测试，先红后绿；Gradle 仅新增 `testImplementation("junit:junit:4.13.2")`。

```kotlin
@Test fun packetIs102BytesAndRepeatsMac() {
    val packet = WakePacket.encode("02:11:22:33:44:55")
    assertEquals(102, packet.size)
    assertArrayEquals(ByteArray(6) { 0xff.toByte() }, packet.copyOfRange(0, 6))
    for (i in 0 until 16) {
        assertArrayEquals(byteArrayOf(2, 17, 34, 51, 68, 85),
            packet.copyOfRange(6 + i * 6, 12 + i * 6))
    }
}
```

- [ ] 实现单播 MAC 校验与编码，纯 JVM 可运行。发送器从 `ConnectivityManager` 选取用户确认的 Wi-Fi `Network` 与 `LinkProperties`，按 IPv4 前缀计算广播；绑定 socket 到该 network，启用 broadcast，目的端口固定 9，不使用目标 IP。
- [ ] 无 Wi-Fi、IPv6-only、/31 或 /32、多个候选 IPv4、VPN 阻止绑定时返回具体错误；不得改向移动数据或全局任意地址。网络被替换/丢失时暂停并要求在前台重新确认，清楚显示原因。
- [ ] JVM 假 transport 用 CountDownLatch 挂起 poll，在 `engine.stop()` 之后释放响应，断言发送计数为 0。再测重复任务仅一个 batch、过期不发送、旧 revision 拒绝、第三包前停止立即中止、Keystore/日志持久化失败不发包。
- [ ] 原生引擎使用单线程 executor，原子 generation/stop 标志；每个 HTTP 请求、授权回包及每次发包前检查。`stop` 同步失效 generation、关闭 active connection/socket、取消等待，随后再发起可失败的服务端 disable；清理不能依赖网络成功。
- [ ] 用 `HttpsURLConnection` 禁止 redirects，设置 connect/read timeout，关闭 error/input streams。按 1/2/4/8/15 秒加抖动退避；成功后复位。401/410 等永久错误暂停并向通知/Flutter 报错，不无限重试。
- [ ] `WakeRelayStore` 在 Android Keystore 中使用 AES-GCM 密钥加密受限 token，SharedPreferences 仅存密文/IV和启用状态；任务 reserve 用同步持久化，先记录再发包，崩溃后宁可提示结果不确定，也不无限重发。
- [ ] 声明 `FOREGROUND_SERVICE_CONNECTED_DEVICE`、`ACCESS_NETWORK_STATE` 和符合网络连接管理用途的必要权限；保留现有录屏服务声明。用户从可见 Activity 启动常驻通知，Android 13+ 请求通知权限；不增加 boot receiver。
- [ ] 通知提供“停止”；Intent/PendingIntent 设置 immutable，服务 `exported=false`，使用独立通知 ID。`START_NOT_STICKY`，进程消失后租约过期，应用恢复显示需重新启用。
- [ ] 增加 `com.qsw.rdesk/wake_agent` MethodChannel，方法 `start`、`stop`、`status`、`openBatterySettings`。`start` 参数为 HTTPS endpoint、agent ID/token，`status` 返回 enabled、networkReady、lastPollAt、errorCode；绝不返回 token。录屏逻辑保持独立。
- [ ] 执行 `./gradlew :app:testReleaseUnitTest`（目录 `flutter_client/android`）及 APK 编译；提交 `feat(android): 增加独立远程开机助手`。

任务 5：Windows 网卡发现、注册与心跳
---------------------------------

**文件：** `windows_wake_service.dart`、`test/windows_wake_service_test.dart`。任务 6 再把本服务接入 Provider。

**接口：**

```dart
class WindowsWakeAdapter {
  final String id, name, mac;
  final bool connected, wired;
  const WindowsWakeAdapter({required this.id, required this.name,
    required this.mac, required this.connected, required this.wired});
}
class WindowsWakeService {
  WindowsWakeService({required WakeApi api,
    required Future<ProcessResult> Function(String, List<String>) run,
    required FlutterSecureStorage storage});
  Future<List<WindowsWakeAdapter>> adapters();
  Future<void> enroll({required String userId, required String deviceId,
    required String name, required String agentId, required String mac});
  Future<void> resume(String userId);
  Future<void> stop();
  Future<void> forget(String userId);
}
```

- [ ] 先测 PowerShell 单对象、数组、空结果、Unicode 网卡名、虚拟/断开/零 MAC 网卡、非零退出码和超时。进程 runner 注入，测试在 macOS 可运行，不冒充 Windows 系统实测。
- [ ] 固定脚本只读查询，不把用户名/MAC 插入命令。`Process.run('powershell.exe', ['-NoProfile','-NonInteractive','-Command', script])`，UTF-8 输出，10 秒总期限；脚本：

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
@(Get-NetAdapter -Physical | Select-Object InterfaceGuid, Name, MacAddress,
    Status, NdisPhysicalMedium) | ConvertTo-Json -Compress
```

- [ ] 物理网卡不等于有线网卡，按 NDIS medium 显示有线/无线/未知；默认推荐已连接且有线的适配器，未知不声称支持 WOL。最终由用户选择并查看 MAC。
- [ ] 新建目标后用 FlutterSecureStorage 保存 target ID/token，key 绑定规范化服务器 URL、账号 ID 和设备 ID；储存失败吊销目标凭据，不报告配置成功。配置目标接口不把普通 presence 当成可信归属证据。
- [ ] 应用处于该账号且用户启用配置时每 10 秒发送一次专用心跳；每次最多一个请求，401 停止并提示重新配置。退出/切换服务器/停用时同步取消 generation，迟到响应不重建计时器。
- [ ] 测试旧账号 token 不用于新服务器、停止后不再心跳、App 未运行时服务端不能判 online。重复配置明确更新/轮换，不每次点击都新建目标。
- [ ] 跑 `flutter test test/windows_wake_service_test.dart` 和 analyze；提交 `feat(windows): 配置开机网卡并报告上线`。

任务 6：账号生命周期与助手控制
----------------------------

**文件：** `wake_agent_channel.dart`、`wake_provider.dart`、`auth_provider.dart`、`app.dart`、`test/wake_provider_test.dart`。

**接口：**

```dart
abstract interface class WakeAgentChannel {
  Future<void> start({required Uri endpoint, required String agentId,
    required String token});
  Future<void> stop();
  Future<WakeAgentStatus> status();
  Future<void> openBatterySettings();
}
class WakeProvider extends ChangeNotifier {
  WakeProvider({required WakeApi api, required WakeAgentChannel agent,
    required WindowsWakeService windows});
  Future<void> bindAccount(String? userId);
  Future<void> refresh();
  Future<void> enableAgent(String name);
  Future<void> disableAgent();
  Future<WakeRequest?> wake(String targetId);
  Future<void> stopForAccountExit();
}
```

- [ ] 构造函数注入 API/channel/Windows service，测试在纯 Flutter 环境不访问真平台。为延迟 enable 响应后退出账号、跨账号切换、快速重复点击和 dispose 后响应编写 Completer 测试。
- [ ] 用 `ChangeNotifierProxyProvider<AuthProvider, WakeProvider>` 接入；`bindAccount` 只在身份变化时清除缓存/计时器、增加 generation，不在每次 auth notify 中重复发请求。
- [ ] `AuthProvider` 增加可注入的 `Future<void> Function()` 退出钩子，默认空操作保证现有测试兼容。显式 logout/会话不可恢复时先调用停止钩子，再清理本地登录；注销仅在服务端成功后清理本地并停止，失败保留账号可用，不误删凭据。
- [ ] `stopForAccountExit` 立即失效本 Provider generation、取消刷新/上线心跳并调用原生 stop，服务端凭据吊销失败也不能阻止本地停止。重新登录不可自动恢复之前显式停用的助手。
- [ ] 若 enable 正在等待创建凭据，退出后响应到达则吊销刚创建的助手，不能启动服务或向新账号缓存写入旧对象。

```dart
final generation = _generation;
final enrollment = await _api.createAgent(name);
if (generation != _generation || _disposed) {
  await _api.revokeAgent(enrollment.id);
  return;
}
// 后续 await 后继续检查 generation，启动与停止由串行生命周期协调。
```

- [ ] 页面可见且请求非终态时每 2 秒查询一次，离开页面停止 UI 查询；平台助手仍由 Kotlin 独立运行。App resume 刷新状态，不自动启动被停用服务。
- [ ] 运行 `flutter test test/wake_provider_test.dart test/auth_session_recovery_test.dart`；提交 `feat(wake): 接入账号隔离与助手生命周期`。

任务 7：操作界面与真实状态文案
----------------------------

**文件：** 新页面/状态组件；设备页、设置页、router 接入；`test/wake_screen_test.dart`、审核真实性测试。

**接口：** `/wake` 为账号目标列表及安卓助手面板，`/wake/setup` 为 Windows 本机开机设置。移动端/macOS 可以请求开机，只有 Windows 显示本机网卡注册，只有 Android 显示助手启用开关。

- [ ] 写 widget 测试：没有 account presence 仍显示离线目标，助手离线禁用开机并说明原因，`sent` 不显示“开机成功”，未知状态不显示“已上线”，未登录提供现有登录入口。
- [ ] 接入设备页操作入口及设置项，不把 wake target 强行塞进原本固定在线的 DeviceDetailScreen，也不新增不存在的 Windows 进入桌面能力。
- [ ] 显示助手最近连接时间、请求发送时间、未确认原因、重试入口及有界历史。状态文案映射：

```dart
String wakePhaseLabel(WakePhase phase) => switch (phase) {
  WakePhase.queued => '请求已提交',
  WakePhase.claimed => '助手正在发送',
  WakePhase.sent => '信号已发送，等待电脑上线',
  WakePhase.online => '电脑已上线',
  WakePhase.unconfirmed => '未确认上线',
  WakePhase.expired => '请求已过期',
  WakePhase.failed => '发送失败',
  WakePhase.cancelled => '请求已取消',
  WakePhase.interrupted => '服务中断，请重新尝试',
  WakePhase.unknown => '状态暂不可用',
};
```

- [ ] Android 设置明确显示常驻通知、供电/后台设置、同一 LAN 条件、停止按钮；锁屏可运行是待实测能力，不将打开开关等同于后台已稳定。
- [ ] 目标删除显示确认对话框，告知仅删除开机配置；Windows 配置引导列出网卡、选择助手和测试发送步骤，不远程自动关机以制造测试条件。
- [ ] 把 120 秒无心跳文案写为“未确认上线；电脑可能已到登录界面，但 RDesk 尚未运行”，不显示“电脑不支持开机”。
- [ ] 运行 widget、账号恢复、审核真实性及现有相关 viewer 回归；提交 `feat(wake): 增加远程开机配置与诊断界面`。

任务 8：端到端验证、文档与发布准备
--------------------------------

**文件：** `docs/remote-wake.md`、`docs/validation/remote-wake.md`、`deploy/privacy.html`、`deploy/support.html`、`deploy/download.html`、`docs/app-store-submission.md`。

- [ ] 建立临时本地服务端、两个测试账号、假原生助手及假目标心跳的完整契约测试。真实 HTTP 串起创建→请求→领取→授权→回执→心跳→状态，并检查未登录/跨账号拒绝；此测试明确标记为模拟链路。
- [ ] 检查测试包/日志不含真实凭据；公开说明增加 MAC、助手绑定及 50 条/7 天诊断记录用途，保留可删除承诺。支持页注明 Windows 远控仍未实现。编辑源页面不等于公开部署，分别列状态。
- [ ] 执行必要验证：

```bash
cargo check --workspace
cargo test -p rdesk_server
```

在 `flutter_client` 执行：

```bash
flutter analyze
flutter test test/wake_api_test.dart test/wake_provider_test.dart test/windows_wake_service_test.dart test/wake_screen_test.dart test/auth_session_recovery_test.dart test/review_truthfulness_test.dart
flutter test test/canvas_rotation_test.dart test/remote_canvas_pointer_test.dart test/session_view_only_test.dart test/connection_history_dedupe_test.dart
flutter test test/remote_action_sheet_test.dart test/remote_key_action_test.dart test/remote_toolbar_controller_test.dart test/desktop_host_action_test.dart
flutter test test/desktop_capture_lifecycle_test.dart test/desktop_host_demand_test.dart
flutter build apk --release
```

- [ ] 枚举已连接设备并确认不是正在承担审核的专用用户，选择可用测试手机安装；多设备时明确 serial，不能盲装第一台。没有合适设备就保存 APK，并在验证记录写清实机未覆盖。iPhone 在可用时运行 `scripts/reinstall_ios.sh` 并检查入口；Windows 二进制必须在 Windows 环境构建/检查，没有该环境就记录未覆盖。
- [ ] 真机测试先验证安卓发出的报文和 Windows 实际启动，再从蜂窝网络控制；分别记录睡眠/休眠/完整关机。不能仅凭 UI 或单次 ping 判成功。
- [ ] 隔夜、24 小时、48 小时三种放置时间分别建记录：目标电源状态、助手供电/锁屏状态、请求时间、领取/发送回执、电脑实际启动及应用上线。未运行阶段写“待验证”。未经用户要求，不自动建立周期自动化或操作电脑关机。
- [ ] 验证记录格式：

```text
场景：完整关机后隔夜，控制端蜂窝网络
状态：待验证
Windows 网卡/系统：实机接入后记录
Android 型号/系统/供电：实机接入后记录
助手最近心跳 / 领取 / 发送 / Windows 上线：只填实测时间
实际电脑是否启动：由现场观察确认
故障定位：助手离线 / 未领取 / 发送失败 / 已发送未确认 / 已上线
```

- [ ] 读取任务 1 保存的工作区差异基线，最终逐文件核对仅新增本功能差异；已有 main.rs/bridge 等修改不得整体暂存。若无法干净拆分，在独立索引验证提交内容，不用 stash、reset 或广泛 revert。
- [ ] 使用 `git diff --cached --check` 和 `git diff --cached --stat` 复核，确保 `AGENTS.md`、既有采集/审核变更未进入提交；最后提交 `docs(wake): 记录配置要求与验证范围`。只在本功能可构建且相关测试通过时按项目要求推送 `origin master`。
- [ ] 输出本地实现、自动测试、平台构建、设备安装、服务端部署、隔夜实测六项实际状态；不能用“完成”掩盖未部署或未实测。服务端部署前提供具体变更、构建/回滚步骤及 public smoke 检查，再取得部署确认。

## 计划自检

- 设计覆盖：持久目标/鉴权/过期/吊销由任务 1–2 承担；跨端 API 由任务 3；独立助手、广播及网络切换由任务 4；账号生命周期由任务 6；Windows 配置/心跳由任务 5；入口和真实状态由任务 7；隐私说明及长期验收由任务 8。
- 接口一致性：JSON 字段、Dart 状态、Kotlin job 和服务端 revision/有效期集中按本文协议实现；禁止各平台自行增加成功状态。
- 审查重点对应的五类失败路径均有明确任务测试；真实手机后台和真实 BIOS 行为仍需实机验证。
- 撤销边界：本机 stop 可同步取消本机待执行工作；跨网络已发出的短许可无法物理收回，不作绝对保证。
- 本计划细化了存储位置、资源限额和发送前二次鉴权，保持已确认设计的功能范围。用户审阅后选择当前会话直接执行或逐任务子代理执行。
