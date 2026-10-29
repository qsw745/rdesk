# 官方服务器配置整改计划

**目标：** 普通版不接受服务器地址修改，账号凭据不会随旧配置发送到其他来源。

**设计：** `docs/superpowers/specs/2026-10-29-official-server-design.md`。沿用 Flutter、SharedPreferences、FlutterSecureStorage；由主代理在当前工作区实施，保留无关未跟踪文件。

## 实施与验证

- [x] 添加网络策略回归：旧恶意地址、裸域名与 HTTP 配置只能产生官方 HTTPS 请求；旧自定义来源的令牌、续登密码、生物识别凭据与信任记录清理；官方旧配置保留；迁移失败不发送请求。
- [x] 移除 `settings_screen.dart` 的网络页面和编辑框、`settings_sections.dart` 的网络标签、`settings_provider.dart` 和 bridge 的地址写入接口。旧网络深链回落常规。
- [x] bridge 强制使用 `AppConstants` 的 HTTPS 来源，首次迁移先清理/绑定凭据，再写完成标记；AuthProvider 读取凭据时检查来源，移除运行时服务器切换接线。
- [x] 本地 HTTP 测试通过测试专用 HttpOverrides 重定向官方请求；不在产品中保留测试地址开关。验证实际请求及被控端上传。
- [x] 执行安全回归、完整 Flutter 测试与 analyze；复核差异、凭据、云 workflow 条件；本地构建并安装到连接的 iPhone，核对版本与启动。
- [x] 补充迁移操作说明及验证证据；交付提交与推送结果以 Git 记录为准。

## 重点边界

迁移不得先覆盖来源再清理凭据；并发初始化必须等待同一迁移；安全存储失败不得跳过清理；官方 HTTP 旧配置升级 HTTPS；局域网直连保持可用；新域名不得继承旧来源凭据；旧深链不得出现失效空页。

## 执行补充

独立复核的两项发现均已修复：清理并绑定安全存储中的可信设备密码（含孤儿键）；校验偏好写入结果并防止失败缓存/未完成写入绕过迁移。对应回归先失败后通过，最终完整测试 367 通过、1 按平台跳过，分析无问题。iPhone 与 Mac 2.3.12（35）均已本地安装启动；详见 `docs/validation/official-server-2026-10-29.md`。
