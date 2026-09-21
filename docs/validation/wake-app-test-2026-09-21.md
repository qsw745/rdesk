# App 2.2.3 开机测试与 Mac 助手

## 本轮范围

- Mac App 内置签名助手，明确选择家庭 LAN，使用账号已有开机 API 启停；Linux 路由器/NAS 助手与安卓助手在同一选择界面中呈现。
- Windows、iPhone/Android、Mac 均可打开目标的「开机测试与诊断」，查看请求 ID、领取、发包回执、应用心跳并复制脱敏报告。网络类型和物理观察由用户填写，不自动推断。观察值只附在本次复制报告里。
- Windows x64 是控制端和 WOL 目标配置端，仍不宣称提供 Windows 被控桌面。没有更改服务器 API，也没有刷路由器或开放公网端口。

## 已完成本地验证

- Go 单测、race 与本地真实 Rust 服务端协议测试通过；进程 stdin EOF 取消验证通过。
- Darwin IP_BOUND_IF 实际接口广播探针通过：负载为普通文本，非 magic packet，没有尝试唤醒真实电脑。
- Flutter 远程开机、账号生命周期、配对、诊断及真实性切片首轮 39 项通过；诊断脱敏修复与 Windows 页面切片再验证 4 项通过。
- 独立代码审查发现助手名可能携带 IP/MAC，被改为报告只包含是否绑定与在线状态，回归覆盖含敏感文本助手名。定向复核通过。
- Windows 本地 Parallels VM：2.2.3 x64 编译、运行 8 秒、Inno 安装与安装后 EXE 摘要一致校验通过。复用该 SDK 已验证的本地平台锁文件，不改变依赖版本；构建后 VM 恢复挂起。
- Mac 双架构 Flutter 构建遇到 ARCHS 被当成单个字符串的问题，改为本地分架构 xcodebuild，Apple Silicon 与 Intel 均编译通过。日常 build_install.sh 构建本机架构，内嵌 helper 为双架构。
- Android 本地 release 构建通过，使用原发布签名配置；未检测到已连接手机，尚不能据此声称安装或设备实测通过。

## 仍待用户测试

- 用户 AX3000T / RD03 / 原厂 2.0.28 没有已验证的 RDesk 安装入口；没有承诺可直接使用。AX6000 使用稳定本身不证明任意 AX6000 都支持 RDesk，仍应核对具体固件/助手来源。
- Mac 保持在家同一网络且唤醒，另一台手机使用蜂窝网络，自行让 Windows 睡眠/关机后测试；收到应用心跳不等于证明 WOL 因果。
- 断网恢复、隔夜、24 小时、48 小时和物理电源状态仍待验收。iOS 公开 App Store 状态与本地构建分别记录，不能由官网下载更新互相推断。

## 最终成品与部署

- Mac Apple Silicon / Intel 成品签名与内嵌 helper 的 Developer ID、TeamIdentifier、Hardened Runtime 校验通过；两种应用与 arm64 DMG 的 Apple 公证均 Accepted，并完成票据附加校验。
- `/Applications/rdesk.app` 已安装 2.2.3（20），保留旧版备份。实际打开界面，选择家庭 en0，账号助手显示「家中 Mac · 在线」；按用户此前 BIOS 已开启的确认，将现有 Windows 配对绑定至该助手，并保存测试配置，没有自动检测 BIOS 或发送真实开机请求。
- 已在安装 App 中执行退出：原 App PID 退出，helper PID 消失；重新打开后未擅自恢复助手。完成验证后重新启用家中 Mac，供用户测试。App、服务端心跳和界面检查不等于物理唤醒成功。
- Android APK 包名 com.qsw.rdesk、版本 2.2.3/20 与原发布签名核验通过。Windows 最终包包含审查后的诊断修复，重新构建、启动与安装校验通过；VM 已恢复挂起。
- iOS 测试版在本地 Xcode 以 IPHONEOS_DEPLOYMENT_TARGET=15.0 构建成功（解决当前 SDK 对旧 Pods 最低版本的构建检查），主包版本2.2.3/20和签名校验通过。没有已连接 iPhone，未安装、未上传 App Store，不把它写为公开更新。
- 官网成品已上传 124.223.200.182 并校验 MANIFEST，current 切换到 releases/20260921-2.2.3；前一版20260921-2.2.2保留，可切回软链接回滚。旧安装包复制保留以兼容现有 URL。没有服务器构建或云 CI。

## Mac 2.2.4（21）到期保护修正

- 2.2.3 的五个官网下载文件全部通过公网 HEAD 长度、Range 和完整下载 SHA-256 校验；旧 2.2.2 Windows URL 仍有效。
- Go 官方 time 文档说明，部分系统的单调时钟会在睡眠时停止。领取请求及每次广播前现同时检查单调时钟与墙钟，到期即拒绝，避免 Mac 恢复后使用旧许可。参考：https://pkg.go.dev/time#hdr-Monotonic_Clocks 。
- Go race 和本地真实 API 协议验证通过；独立复核未发现阻塞问题。边界单测未模拟真实系统睡眠或两个时钟的分歧，跨睡眠物理测试仍待完成。
- 2.2.4 本地包复用 2.2.3 已验证且未改动的 Flutter UI 二进制，重新本地编译双架构 helper、更新主包 Info.plist 版本为 2.2.4/21，再签名并验证两架构主包/helper。Windows 与 Android 仍为 2.2.3/20，iOS 本地包仍为 2.2.3/20。
- Apple 公证暂时受阻：默认与显式 login.keychain-db 均返回找不到既有 rdesk 凭据；没有上传成功，不将 2.2.3 的公证票据当作 2.2.4 的公证结果。官网暂保留已验证的 2.2.3 下载，未覆写其固定文件内容。
- 本机 `/Applications/rdesk.app` 已安装本地签名的 2.2.4/21，版本与主包/helper 签名核验通过，旧版留在 `/Applications/.rdesk-wake-backup-20.app`。启动后账号恢复，Windows 在线状态可见；更新退出了旧助手，新版助手尚未重新启用，需在「远程开机」打开 Mac 助手并选择家庭网络。此次未验证物理唤醒。
