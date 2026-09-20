# 官网与多平台安装包发布验证（2026-09-20）

## 安装包来源

- 功能源代码：`6ca27450352ab6aa36fa0bb0b7dc655391353395`，从干净 Git 导出目录构建，未打入工作区未提交改动。
- 构建配置：`e33d88484b3be16481924479d54cafdc1df14def`；macOS 最低版本升至 12，Windows CI 修复文件校验生成。
- macOS / Android / Windows 使用构建版本 `2.1.1+15`，仓库默认版本未用于覆盖 App Store 版本。
- Windows CI：https://github.com/qsw745/rdesk/actions/runs/35487764888 ，构建、启动 8 秒、安装程序生成和静默安装均通过。
- Android：APK `com.qsw.rdesk`，versionName `2.1.1`，versionCode `15`，minSdk `24`，targetSdk `36`，v2 发布签名验证通过。

## macOS 公证

- Apple 芯片应用公证：`a254bfb1-f3c0-4c34-9dbc-3184f03d3106`，Accepted。
- Intel 应用公证：`e5f1e1d0-f4ba-4dc6-a379-373b145d7154`，Accepted。
- Apple 芯片 DMG 公证：`944fec79-a84e-4007-b340-7267e2b26f00`，Accepted。
- 两个应用均完成票据装订；Apple 芯片 DMG 完成签名、公证、装订。Intel 最终提供包含已装订应用的 ZIP。
- `codesign --verify --deep --strict`、`stapler validate` 通过；`spctl` 识别 Notarized Developer ID，但当前主机同时报告 `override=security disabled`，不能替代默认 Gatekeeper 设置机器的首次安装验收。
- Xcode 27 的多架构 `lipo -verify_arch` 行为使通用构建失败，因此分别构建 arm64 / x86_64。未修改系统 SDK。

## 官网

- 页面数据源：`deploy/releases.json`，生成器：`scripts/render_download_page.py`。
- GitHub Pages：`https://qsw745.github.io/rdesk/`。
- 保留原域名 SiteHarbor 根站与旧下载页；服务器 SSH 超时期间不改 nginx 或重启生产服务。
- 本地浏览器检查桌面 1280 宽、手机 390×844 排版，下载按钮与说明可见，无占位符；页面包含四个平台入口。
- iOS 公开入口：`https://apps.apple.com/cn/app/id6796165712`。Apple lookup 返回 RDesk 远程桌面 2.1.0，iOS 13+。
- 不发布普通 IPA，不修改 App Store 元数据或发起新审核。

## 能力边界

- 远程开机配套服务尚未部署；页面和发布说明明确标注。
- 当前 App Store 2.1.0 不包含远程开机，Windows 当前不支持远程桌面被控。
- 硬件唤醒、隔夜与 24/48 小时验收尚未覆盖。
- Windows 包尚未配置发布者签名。

## 公网验收

- GitHub Pages 发布任务 `35488412647` 成功，官网已在真实浏览器回读显示四个平台入口。
- GitHub Release `v2.1.1` 已公开发布，五个安装文件的服务端摘要均与本地 SHA-256 一致。
- 从公开下载 URL 完整下载了五个文件，逐一核对长度及 SHA-256，全数通过。
- 官网、下载页、支持页、隐私页、图标和校验值文件的 GET / HEAD 均通过；官网 HTML 与本地生成文件逐字节一致。
- 原服务器后续 `/health` 15 秒请求超时；SSH TCP 可建立但 banner 超时。本轮服务器编译连接已终止，无法通过 SSH 核实远端编译是否退出。未重启服务，未替换生产二进制，已请求云控制台排查授权。
