# 本地构建与官网下载更新

所有平台先在本机、或本机容器／虚拟机中编译与验证。生产机只接收成品；GitHub 仅保留源代码与历史发行记录；正式官网和安装包由自有服务器提供，不承担云端构建。

## Windows

在本地 Windows 电脑或本地 Windows 虚拟机安装 Flutter、Visual Studio 2022 C++ 桌面工具（含 ATL、Windows SDK、CMake）和 Inno Setup 6.7 或更新版本（安装器使用其深色模式、背景图和 windows11 风格）。当前插件不兼容 VS 2026 的旧协程开关，脚本明确选择 VS 2022。

安装器为简体中文、品牌化界面：素材由 `python3 design/generate_installer_art.py` 生成到 `scripts/installer/`，中文文案在 `scripts/installer/ChineseSimplified.isl`。「开机后自动启动」安装选项与 App「设置 → 常规 → 启动」共用当前用户 `Run` 项 `RDesk`；升级时按实际状态预选，静默安装不改动，卸载时移除。

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

脚本按 `flutter_client/pubspec.yaml` 读取版本，锁定依赖，构建 x64，附带 VC++ 运行库，检查启动、生成安装包和便携 ZIP，并静默安装到临时目录核对主程序。输出到 `dist/`。启动与安装验证不代表真实硬件网络唤醒通过。

如需依赖镜像，仅使用可信的 Flutter 镜像；切换托管地址时保留锁文件中的精确版本与内容摘要。可预先下载官方 NuGet 包到本地缓存，并在构建副本中用 NuGet.Config 指向缓存。

## macOS

```sh
bash scripts/release_macos.sh arm64    # dist/RDesk-<版本>-macos-arm64.dmg
bash scripts/release_macos.sh x86_64   # dist/RDesk-<版本>-macos-x64.zip
```

脚本按架构独立构建，内嵌并签名开机助手，Developer ID 签名后公证并装订应用；arm64 另制作带「应用程序」快捷方式的 DMG，再单独签名、公证、装订。需要登录钥匙串中的 Developer ID 证书与 notarytool 配置 `rdesk`（见 [macOS 分发](macos-distribution.md)）。

同一工作目录内的构建须串行。两个 macOS 构建入口会先清理 Flutter 构建图及共享的原生库输出，避免切换 Apple 芯片／Intel 架构时复用错误框架。`scripts/verify_macos_install.sh` 在签名检查前扫描全包 Mach-O：每个框架、原生库和助手都必须包含主程序的全部架构；Developer ID 签名或公证通过不能替代这项检查。

需要验证原生缓存接口及真实下载时，可在隔离的签名 Release 副本中使用 `flutter_client/tool/update_probe.dart` 作为入口。它不启动远控、不读取账号，调用真实路径接口并使用正式更新服务下载及校验。诊断版不能用于正式发行；恢复默认 `lib/main.dart` 后重新构建正式应用。下载校验通过仍须独立检查下载包内的架构。

## Android

在本地配置原发布签名，执行 `flutter build apk --release`。用 Android SDK 的 `apksigner verify` 核对签名、`aapt dump badging` 核对包名与版本；存在已连接测试手机时覆盖安装验证。不要把密钥、口令或本地签名配置提交到仓库。

## 官网与发行附件

正式官网：https://qisw.top/rdesk/ 。页面和安装包在 `124.223.200.182`，域名入口沿用 `101.37.21.147` 的 HTTPS 反向代理；不改整个域名的 DNS 或已有产品入口。

1. 在本地构建并验证安装包，更新 `deploy/releases.json` 中的平台版本、`https://qisw.top/rdesk/dl/` 地址、字节数及 SHA-256。
2. 执行 `python3 scripts/prepare_website.py` 生成静态页面。
3. 执行 `python3 scripts/package_website.py --artifacts <安装包目录> --output <本地成品.tar.gz>`；多个目录可重复传入 `--artifacts`。脚本核对全部安装包并打包页面，缺失或摘要错误会中止。
4. 上传成品到 `rdesk-new`（SSH 用户 ubuntu），解压至 `/opt/rdesk-website/releases/<版本>`，执行 `sha256sum -c MANIFEST.sha256`，将所有者设为 root:root，并确保 nginx 可读。
5. 原子切换 `/opt/rdesk-website/current`，只保留当前版和上一版两个目录（上一版用于回滚）；更早的目录在切换并核对后删除。新目录除清单内的安装包外，只额外带上一版的安装包：更新器把清单缓存最长 6 小时。删除时写死绝对路径，不用变量拼接。例如在该目录下创建 `current.next` 相对链接，再用 `mv -Tf current.next current` 替换。
6. 验证公开页面、HEAD、Range 断点续传和下载文件摘要。更新域名入口或源站 nginx 前，先备份、执行 `nginx -t`，再平滑重载。

首次部署与回滚路径见 [自有服务器迁移记录](validation/website-self-hosted-2026-09-20.md)。配置模板分别为 `deploy/nginx.rdesk-website-origin.conf` 与 `deploy/nginx.rdesk-website-edge.conf`，均为 server 内的片段，不能当完整虚拟主机文件使用。

Windows 安装包目前没有发布者签名。iOS 仍通过 App Store 分发，上架更新需要独立的本地打包与审核流程，不能把官网下载页更新当作苹果手机版本已更新。

## 2.2.0 扫码配对发行注意

先部署并验证新服务端，再发布客户端。可在本地运行 `python3 scripts/check_wake_pairing.py --base https://qisw.top` 验证真实 HTTP 协议；脚本只创建自己的临时账号并在结束时删除，模拟回执不代表物理电脑已唤醒。

Windows 生成短时二维码，新版 iPhone/Android 扫码后完成家庭助手、BIOS 和测试。相机只在用户开启扫码时使用，长期心跳凭据保存在 Windows 安全存储。iOS 2.2.0 本轮仅本地构建，不随网站更新自动进入 App Store。完整验证和未覆盖项见 [2.2.0 验证记录](validation/cross-platform-redesign-2026-09-20.md)。
