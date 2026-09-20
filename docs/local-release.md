# 本地构建与官网下载更新

所有平台先在本机、或本机容器／虚拟机中编译与验证。生产机只接收成品；GitHub 仅保留源代码与历史发行记录；正式官网和安装包由自有服务器提供，不承担云端构建。

## Windows

在本地 Windows 电脑或本地 Windows 虚拟机安装 Flutter、Visual Studio 2022 C++ 桌面工具（含 ATL、Windows SDK、CMake）和 Inno Setup 6。当前插件不兼容 VS 2026 的旧协程开关，脚本明确选择 VS 2022。

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

脚本按 `flutter_client/pubspec.yaml` 读取版本，锁定依赖，构建 x64，附带 VC++ 运行库，检查启动、生成安装包和便携 ZIP，并静默安装到临时目录核对主程序。输出到 `dist/`。启动与安装验证不代表真实硬件网络唤醒通过。

如需依赖镜像，仅使用可信的 Flutter 镜像；切换托管地址时保留锁文件中的精确版本与内容摘要。可预先下载官方 NuGet 包到本地缓存，并在构建副本中用 NuGet.Config 指向缓存。

## Android

在本地配置原发布签名，执行 `flutter build apk --release`。用 Android SDK 的 `apksigner verify` 核对签名、`aapt dump badging` 核对包名与版本；存在已连接测试手机时覆盖安装验证。不要把密钥、口令或本地签名配置提交到仓库。

## 官网与发行附件

正式官网：https://qisw.top/rdesk/ 。页面和安装包在 `124.223.200.182`，域名入口沿用 `101.37.21.147` 的 HTTPS 反向代理；不改整个域名的 DNS 或已有产品入口。

1. 在本地构建并验证安装包，更新 `deploy/releases.json` 中的平台版本、`https://qisw.top/rdesk/dl/` 地址、字节数及 SHA-256。
2. 执行 `python3 scripts/prepare_website.py` 生成静态页面。
3. 执行 `python3 scripts/package_website.py --artifacts <安装包目录> --output <本地成品.tar.gz>`；多个目录可重复传入 `--artifacts`。脚本核对全部安装包并打包页面，缺失或摘要错误会中止。
4. 上传成品到 `rdesk-new`（SSH 用户 ubuntu），解压至 `/opt/rdesk-website/releases/<版本>`，执行 `sha256sum -c MANIFEST.sha256`，将所有者设为 root:root，并确保 nginx 可读。
5. 保留旧目录和 current 链接，原子切换 `/opt/rdesk-website/current`。例如在该目录下创建 `current.next` 相对链接，再用 `mv -Tf current.next current` 替换。
6. 验证公开页面、HEAD、Range 断点续传和下载文件摘要。更新域名入口或源站 nginx 前，先备份、执行 `nginx -t`，再平滑重载。

首次部署与回滚路径见 [自有服务器迁移记录](validation/website-self-hosted-2026-09-20.md)。配置模板分别为 `deploy/nginx.rdesk-website-origin.conf` 与 `deploy/nginx.rdesk-website-edge.conf`，均为 server 内的片段，不能当完整虚拟主机文件使用。

Windows 安装包目前没有发布者签名。iOS 仍通过 App Store 分发，上架更新需要独立的本地打包与审核流程，不能把官网下载页更新当作苹果手机版本已更新。
