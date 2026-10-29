# 官方服务地址整改验证（2026-10-29）

## 改动与范围

- 本地候选版本：2.3.12（35）。普通设置移除「网络」和服务器编辑框，旧网络深链回落常规。
- 账号与官方中继只从随应用交付的配置取得 HTTPS 来源；旧偏好不再决定请求目标，也没有运行时地址写入接口。
- 迁移先处理账号、自动续登、生物识别及可信设备密码（包括安全存储孤儿键），再删除旧地址、持久化完成标记。官方旧配置可保留；自定义来源/域名变化要求重新登录。
- 记住的密码绑定来源；账号请求拒绝跟随重定向。安全存储或偏好持久化失败均阻止迁移，重试前重新读取持久数据；并发请求等待完成标记写入成功。
- 保留现有局域网直连。官方中继仍可解析内容，本次没有实现端到端加密。

## 本地测试

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：367 项通过、1 项按平台跳过（`windows_process_runner_test.dart`，本机 macOS）。
- 新增 `official_server_policy_test.dart` 共 17 项：官方请求目标、账号旧来源清理/保留、设备密码与孤儿键、续登隔离、实际 JPEG 上传、并发迁移、重定向、安全存储故障、完成标记写入返回失败/抛错/未完成时的等待。
- 原始不安全路径先由失败测试复现，再修复为通过。测试通过传输层把官方目标接到本地假服务器，并拒绝其他外网地址；没有向线上或其他主机发送测试凭据/输入。
- 独立只读复核发现的「遗留设备密码」及「完成标记写入失败/缓存」两项均补了失败测试并修复，随后运行完整测试。
- 未运行 Windows 原生构建或 Android 真机安装；跨平台共享行为通过上述 Flutter 测试验证。

## 安装与发布

- iOS：`flutter build ios --release --no-pub` 成功，产物 `build/ios/iphoneos/Runner.app`；`codesign --verify --deep --strict` 通过。主 App 与 Broadcast Extension 的版本/构建均为 2.3.12（35）。
- 真机：通过 `devicectl` 覆盖安装到已配对的 iPhone 17 Pro Max，`device process launch --terminate-existing com.qsw.rdesk` 成功；随后从设备应用清单读回「随控」版本 2.3.12、构建 35。安装使用原 Bundle ID，保留现有应用数据。
- macOS：`./build_install.sh macos` 完成本地 arm64 release 构建、内嵌通用开机助手、Developer ID 签名及 Hardened Runtime/全部 Mach-O 架构校验，备份旧版并安装到 `/Applications/rdesk.app`；构建成品与安装副本均通过 `verify_macos_install.sh`。
- 实际 Mac 界面：已保留的官方账号正常加载设备列表；设置仅显示「常规 / 安全 / 关于」，没有网络标签与地址编辑项；「关于」显示 2.3.12（35）。仅打开本机设置/关于，没有连接或向其他设备发送输入。
- Mac 旧版备份：`/private/tmp/rdesk-macos-install.DVQfOF/rdesk.app`。本地候选未做 Apple 公证，不是公开下载版本。

此次不发布官网、不上传商店、不部署服务端。`.github/workflows/` 无 workflow 文件，推送不会触发仓库内云构建。
