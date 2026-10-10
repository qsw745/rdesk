# Windows 被控端

状态：第一阶段已实现并在本地 Windows 虚拟机中验证，尚未发布，服务端新字段尚未部署。当前发布版 Windows 仍只能作为控制端。实现与方案不一致之处已在文中改为实际做法；验证记录见文末。

## 现状

- `DesktopHostProvider` 的托管意图、按需采集租约、LAN/中继指令分发与平台无关，已可复用；只有恢复循环和权限刷新两处写死 `Platform.isMacOS`。
- `DesktopHostService` 的采集、点击、拖动、文本、按键、剪贴板全部只有 macOS 分支，Windows 返回空或 `false`。
- `windows/runner` 只有 `com.qsw.rdesk/window`（托盘）和 `com.qsw.rdesk/windows_wake` 两个原生通道，没有 `com.qsw.rdesk/desktop_host`。
- 观看端只识别 `peerOs` 含 `mac` 或 `android`；Windows 被控端会落入「未知平台」，不展示任何桌面按键。
- 服务端 `AccountPresence` 只有 `platform`，没有版本或能力字段，设备列表无法区分新旧 Windows 客户端，所以 `DeviceAbilities` 目前对所有 Windows 设备一律禁用。

## 范围

第一阶段只做「已登录且未锁屏的 Windows 会话」被查看和控制，中继与局域网两条路径都支持。

明确不在第一阶段：

- 锁屏界面、登录界面、UAC 安全桌面的画面与输入。它们属于 Winlogon 桌面，用户会话里的普通进程既采不到也注入不了，需要 SYSTEM 服务加会话内代理，单独立项为第二阶段。
- 以管理员身份运行的窗口。UIPI 会丢弃低权限进程发来的输入；绕过需要 `uiAccess=true`，而它要求安装包带发布者签名并装在受保护目录，当前安装包未签名且装在 `%LOCALAPPDATA%`。画面可见，输入无效。
- 发送 Ctrl+Alt+Del、文件传输之外的新功能、音频、多显示器同时查看。

由此带来一个必须如实告知的产品限制：远程开机后电脑停在登录界面，随控要到用户登录后才启动（HKCU `Run`）。「远程开机后直接远程控制」只在这台电脑配置了 Windows 自动登录时成立；应用不替用户开启自动登录，只在说明里写明。

## 原生层

新增 `windows/runner/desktop_host_bridge.{h,cpp}` 注册 `com.qsw.rdesk/desktop_host`，方法名与返回结构沿用 macOS 契约，Dart 侧不为 Windows 另开一套通道。采集和输入都在 bridge 的一个工作线程上执行，结果经窗口消息回到平台线程。按职责拆分：

采集 `screen_capture.{h,cpp}`

- 主路径 DXGI Desktop Duplication：按所选显示器建立 `IDXGIOutputDuplication`，`AcquireNextFrame` 取帧，缩放到 `maxDimension` 后用 WIC 编码 JPEG，直接返回内存字节。不引入第三方库。
- 每次采集先检查输入桌面：锁屏返回 `SESSION_LOCKED`，UAC 等安全桌面返回 `SECURE_DESKTOP`，并立即丢弃保留的画面，不回退。`DXGI_ERROR_ACCESS_LOST`（分辨率变化、切换桌面）时销毁并重建。
- 新建的复制在静止屏幕上给出的第一帧是空画面（`LastPresentTime` 为 0）。这种帧一律不用；等不到真实画面时首帧走 GDI，之后的变化仍由复制提供。实测中直接使用该帧会把纯黑画面当作成功返回。
- 仅在 Duplication 不被支持（部分虚拟机、远程桌面会话）或显示器被旋转时回退到 GDI `BitBlt`，并在诊断里标明使用的路径。
- 静止画面 `AcquireNextFrame` 超时属正常：返回上一帧的缓存 JPEG，时间戳不变，让上层按既有静态帧逻辑处理；不能把「没有新帧」当成采集失效。
- 采集和编码在独立工作线程，结果回到平台线程后再 `result->Success`；`setCaptureEnabled(false)` 与 generation 变化要取消在途请求并释放 Duplication，与 macOS 的 `cancelCapture` 语义一致。没有观看租约时不持有任何采集资源。
- 鼠标指针不合成进画面，沿用观看端本地指针层。

输入 `input_injector.{h,cpp}`

- 一律 `SendInput`。坐标由归一化值映射到所选显示器矩形，再换算为虚拟桌面的 0–65535（`MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`）。进程已是 PerMonitorV2，全部使用物理像素。
- 映射写成不依赖系统调用的纯函数（显示器矩形 + 虚拟桌面矩形 → 绝对坐标），覆盖副屏在左侧/上方的负坐标和不同缩放比例。
- `tap` 左键单击，`long_press` 右键单击，`drag` 左键按下后插值移动再抬起，滚动用 `MOUSEEVENTF_WHEEL`。
- 文本用 `KEYEVENTF_UNICODE` 逐码元发送，正确处理代理对，不经剪贴板。
- 按键用虚拟键码加修饰键，并带上对应的硬件扫描码，按下与抬起成对发送，异常路径也要抬起修饰键，避免对端留下「卡住的 Ctrl」。扫描码不能省：原生控件只看虚拟键码，Flutter 窗口按扫描码识别按键，缺少时 Ctrl 不被当作修饰键（实测 Ctrl+A 变成普通的 A）。
- `SendInput` 返回的已插入事件数小于请求数即视为失败并如实返回 `false`（前台是提权窗口时会出现）。

显示器 `display_list.{h,cpp}`：主显示器在前，其余按位置排序，采集和输入共用同一份序号。

会话状态不单独监听：采集时用 `OpenInputDesktop` 判断输入桌面，再用 `WTSQuerySessionInformation` 区分锁屏与安全桌面。`wake_screen` 用 `SetThreadExecutionState(ES_DISPLAY_REQUIRED)` 加一次往返的鼠标位移点亮显示器。

坐标换算、缩放尺寸、拖动路径等算术集中在不依赖 Windows 头文件的 `host_geometry.h`。

`CMakeLists.txt` 增加源文件并链接 `d3d11`、`dxgi`、`windowscodecs`、`wtsapi32`。

## Dart 层

- `DesktopHostService`：Windows 分支经 `WindowsHostDriver` 全部走通道，不启动子进程。新增鼠标类通道方法 `performMouse`（click / rightClick / drag / scroll），以后 macOS 可迁到同一契约。剪贴板用 Flutter `Clipboard`。
- 新增 `windowsRemoteKeyStrokeForAction`，与 `remote_key_action.dart` 的 macOS 映射并列：方向键、Esc、Tab、空格、Enter、Delete；`key_command_*` 映射为 Ctrl 组合（重做为 Ctrl+Y）；`show_desktop`（Win+D）、`task_view`（Win+Tab）。旧版观看端对非 Mac 被控端只显示安卓的返回/主页/任务，这三个动作在 Windows 上分别对应 Alt+←、Win+D、Win+Tab。
- `DesktopHostProvider`：恢复循环对 Windows 开放；`SESSION_LOCKED` 映射为明确提示「电脑已锁屏，解锁后才能查看画面」，不进入权限拒绝的冷却逻辑。`SECURE_DESKTOP` 提示「电脑正在显示系统安全界面，暂时无法查看画面」。
- `PlatformCapabilities`：`canHost`、`canUnattendedHost` 加入 Windows。
- 观看端 `RemoteControlBar` / `RemoteKeyboardSheet`：`peerOs` 含 `windows` 时展示 Windows 动作与 Ctrl 系按键；未知平台仍不展示。
- 「远程协助」页移除 `_HostUnsupportedCard`，使用与 Mac 相同的托管卡片；设置页出现桌面被控入口。

## 知情与安全

Windows 没有系统级的录屏或辅助功能授权弹窗，告知责任完全在应用内，这一部分不能省。

- 托管默认关闭，由用户在本机手动开启；升级安装不自动开启。此前桌面端一启动就自动开始托管，Windows 改为只恢复用户上次在开关上的选择（`HostingIntentStore`）；Mac 仍是启动即待命，由系统授权把关，行为未变。
- 无人值守必须设置密码，复用现有服务端密码校验与可信设备逻辑，不新增免密路径。
- 被访问期间：托盘提示文字改为「随控 · 正在被远程查看」，开始时弹出一次系统通知。「被访问」不只指取画面：只发输入或只读剪贴板的会话不持有屏幕租约，同样计入（最后一次操作后保持 10 秒）。即使用户关闭了「关闭到托盘」，期间也保留托盘图标，资源管理器重启后会重新添加。托盘图标本身的样式和对端设备名尚未实现。
- 托盘菜单在被访问期间多出两项：「断开远程查看」先清空受信查看端并更换临时验证码，再断开并重新待命，被断开的一方不能凭旧凭据立刻回来（用户自设的永久密码不会被改动）；「停止被远程控制」直接关闭被控并记住这个选择。
- 设置页诊断区的「重启共享服务」在被控关闭时不可用，不能借它绕过开关。局域网认证在本机密码为空时一律拒绝。
- 锁屏或出现系统安全界面时，原生层丢弃保留的画面，Dart 层同时清空已缓存的那一帧，局域网取帧改为返回 503。中继服务器上已上传的最后一帧仍按其 30 秒有效期过期，这一点未处理。
- 输入在注入前检查：锁屏或安全桌面上不发送；目标窗口所属进程的完整性级别高于随控（以管理员身份运行）时直接返回失败。后者是因为 Windows 会丢弃这类输入却仍报告成功。
- 租约到期或会话关闭后立即释放采集资源，托盘恢复常态。
- 日志不记录键入文本、剪贴板内容和密码。

## 能力标识

设备列表需要知道某台 Windows 电脑能否被控，否则要么继续一律禁用，要么对旧版本给出点了没反应的按钮。

- 服务端 `AccountPresence` 与登记请求增加可选 `can_host`（`serde(default)` 为 `false`），随账号设备列表返回。它只来自客户端自己的上报，不能由「已登记为主机」推断：已发布的旧版 Windows 客户端启动时就会登记为主机，只是采不到画面。
- 设备列表同时返回 `hosting`（该设备当前是否持有未过期的主机登记）。
- 客户端登记时上报 `PlatformCapabilities.current.canHost`。`DeviceAbilities` 对 Windows 的判断：`can_host` 为假显示「这台电脑上的随控版本较旧，更新后才能被远程控制」；`can_host` 为真但 `hosting` 为假显示「这台电脑未开启远程控制」；两者都满足才出现连接按钮。
- 收藏与历史条目没有能力信息，Windows 条目保持可按设备码连接，由连接结果说明原因。
- 服务端先部署，客户端后发布；公网入口无需新增路由。

## 验证

可重复的检查：

- `cargo test -p rdesk_server`（含 `account_tests`：新旧客户端混合登记、登记不等于具备能力、过期登记不算托管中）。
- `flutter test`：`windows_host_driver_test`、`hosting_intent_test`、`desktop_window_service_test`、`desktop_host_lan_listener_test`、`desktop_capture_errors_test`、`settings_capabilities_test`、`remote_action_sheet_test`、`device_directory*`、`device_direct_connect_test`，以及原有的桌面采集生命周期与按需托管测试。
- `windows/runner/tests/host_geometry_test.cpp`：坐标与尺寸换算，任意机器可编译运行。
- `windows/runner/tests/build_native_tests.cmd` 构建 `host_smoke.exe`，须在已登录、未锁屏的用户会话中运行：`capture` 显示一块已知颜色的窗口并在解码后的结果里核对该颜色（空白帧无法通过），`capture <文件> 1920 gdi` 强制走 GDI 路径，`input` 驱动自带的测试窗口并读回实际收到的内容。

2026-10-10 在本地 Parallels「Windows 11」虚拟机（单显示器 3456×1916）的结果：

- 应用以 `/W4 /WX` 构建通过，`build_windows.ps1` 的启动与安装器检查通过。
- `host_smoke capture`：DXGI 与 GDI 两条路径均通过，包括静止屏幕首帧、画面变化、重复采集、改变尺寸、释放后重新采集。
- `host_smoke input`：点击落点与目标像素一致，中文与非 BMP 字符输入完整，Ctrl+A、退格、方向键、拖动选中、滚轮、右键、越界与非法按键拒绝均通过。
- 应用端到端（经应用自身的局域网接口）：开启开关前 21116 端口未监听；无令牌取帧、无令牌点击、错误密码认证均返回 401；认证后取帧 1920×1064；连续 10 次点击每次都切换了页面；在 Flutter 输入框中文字输入、Ctrl+A 加删除清空、方向键移动光标均生效；不支持的动作返回 `ok=false`；关闭会话后旧令牌返回 401；被查看时托盘通知「这台电脑正在被远程查看」实际弹出；开启后退出再启动，未操作界面即恢复监听。

实测中发现并修正的问题：

- DXGI 新建复制后的空白首帧被当作成功画面返回（纯黑）。
- 按键事件不带扫描码时，Flutter 窗口不把 Ctrl 识别为修饰键。
- 启动时可用性循环与托管切换同时建立局域网监听，后一个覆盖前一个的引用，关闭被控后仍残留一个监听端口（请求一律 503，但端口未关）。现在并发调用共用同一次绑定，见 `desktop_host_lan_listener_test`。

尚未验证：

- 经公网中继的查看与控制，以及从 Mac 或手机的随控实际连接这台 Windows。
- 实体 Windows 电脑、多显示器（含副屏在左侧）、非 100% 缩放下的实际表现；这些只有纯函数测试覆盖。
- 锁屏与 UAC 弹窗时的实际返回；对管理员窗口的输入被识别并返回失败（完整性级别判断只读过代码，没有在提权窗口上实测）。
- 分辨率或缩放在观看期间改变后的画面与坐标。
- 托盘「断开远程查看」「停止被远程控制」菜单项的实际显示和点击（通知本身已见到；对应的 Dart 行为有单元测试）。
- 虚拟机挂起再恢复后应用窗口内容变黑，重启应用后正常；未确认实体机睡眠唤醒后是否有同样现象。

## 独立审查

实现后请两个独立审查分别看了原生代码和安全相关改动，没有发现严重级别的问题。已按意见修改的见上文各节。确认存在但不在本次范围内的：

- 临时验证码只有 6 位（约 30 bit），重启后不变，界面叫「临时」实际长期有效；服务端和局域网认证都没有失败限速。Windows 没有系统授权把关，这一条的风险比在 Mac 上更大，建议在发布前解决。
- 局域网通道是明文 HTTP，令牌没有空闲过期，请求体没有大小上限，`/health` 无需认证即返回是否有人在看。均为既有实现。
- 同账号设备经中继免密码、免确认即可控制，属产品设计，首次开启被控时应向用户说明。

## 发布与文案

- 所有构建在本机完成：Windows 仍用虚拟机内 `scripts\build_windows.ps1`。
- 同步修改 `deploy/support.html`、`deploy/download.html`、应用内说明、`review_truthfulness_test.dart`、`AGENTS.md` 的能力边界；独立托管的 `rdesk-support` 页面另行更新。App Store 元数据不提及 Windows。
- 文案必须写明三项限制：锁屏和登录界面不可控、管理员窗口不可操作、远程开机后需已登录才可控制。

## 风险

- 未签名的安装包加上屏幕采集与输入注入，更容易被 SmartScreen 和杀毒软件拦截。发布者签名建议与本功能同期解决，它也是以后 `uiAccess` 的前提。
- 采集走轮询加 JPEG，与现有 macOS 管线一致，流畅度受限于该架构；本方案不改变传输层。
- 第二阶段的 SYSTEM 服务会改变安装方式（需要管理员权限安装），届时安装目录、更新器和自启动都要重新设计，不在本方案内预埋。

## 分步

1. 服务端 `can_host` / `hosting` 字段与测试（已完成，未部署）。
2. 原生采集、输入与通道，Dart 侧分支与按键映射，观看端 Windows 动作（已完成）。
3. 托管开关与意图持久化、托盘提示与断开入口、设备列表能力判断与应用内文案（已完成）。
4. 部署服务端；经中继和实体机做端到端验证；补上「尚未验证」各项。
5. 更新对外页面与 `AGENTS.md` 的能力边界，本地构建并发布。
