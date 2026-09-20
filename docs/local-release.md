# 本地构建与官网下载更新

所有平台先在本机、或本机容器／虚拟机中编译与验证。生产机只接收成品；GitHub 用于源代码、发行附件和静态页面托管，不承担源代码构建。

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

1. 将已验证的安装包上传到 GitHub Release，并提供 SHA256SUMS.txt。
2. 修改 `deploy/releases.json`，填写各平台实际版本、公开地址、字节数和 SHA-256；未更新的平台保留旧版本与能力说明。
3. 在本地执行 `python3 scripts/prepare_website.py`，生成 `deploy/site/`。
4. 提交生成的页面和元数据。`website.yml` 只上传该目录并部署 GitHub Pages，不执行页面生成或应用构建。
5. 回读公开页面，下载发行文件并核对摘要。确认完成后再报告官网已更新。

Windows 安装包目前没有发布者签名。iOS 上架更新需要独立的本地打包与 App Store 流程，不能把官网下载页更新当作苹果手机版本已更新。
