# 2.3.2 发布记录（2026-09-29）

## 内容

- 源码：提交 `b90c7dd`（版本 2.3.2+25），包含：
  - 应用改名为「随控」（`58f26a3`、`4df7980`）：各平台安装后显示名、应用内文案、通知与无障碍名称、官网模板、隐私政策与支持页（写作「随控（原名 RDesk）」）。包名、Bundle ID、`rdesk.app`/`rdesk.exe`、安装目录、下载文件名、服务器路径和协议头保持不变。
  - Windows：关闭窗口最小化到托盘、开机自启（`--hidden` 直接进托盘）、单实例、全新中文安装器（`d6ca8d1`、`17acdec`）。
  - macOS：设置中的登录后自动打开；修正菜单 `APP_NAME` 占位符与 com.example 版权。
- 发布 macOS、Windows、Android。iOS 未变：商店仍为 2.1.0，iOS 显示名待下个版本与 App Store Connect 名称一起改为「随控远程」。服务端无需改动。

## 构建（全部在本机或本机虚拟机完成）

| 文件 | 字节 | SHA-256 | 验证 |
| --- | --- | --- | --- |
| RDesk-2.3.2-macos-arm64.dmg | 16833000 | `2b0d63bcdcba71cf8a2ddadf82eacde4d5aa44e2b93ce74f8653b516273d67c0` | 应用与 DMG 分别公证 Accepted 并装订；`spctl` 为 Notarized Developer ID；DMG 卷名「随控」 |
| RDesk-2.3.2-macos-x64.zip | 16441230 | `eee203726a1a217a1799632b0aefbb9adc4c50f597a7dc3a39e844cf2c0225bd` | 主程序 x86_64；公证 Accepted 并装订 |
| RDesk-2.3.2-windows-x64-setup.exe | 13164648 | `f6b1031d07ac566776fe36f1d9ad1270fad49aaa9b55aa9574d23115c594406b` | Parallels Windows 11 + VS2022 + Inno Setup 6.7：x64、启动存活、静默安装后主程序摘要一致；无编译警告 |
| RDesk-2.3.2-windows-x64-portable.zip | 14203360 | `816fe47a568974806f735c93884e21db8b34f758a51e23ac1a36dd95c2c25c5d` | 同上构建产物 |
| RDesk-2.3.2-android.apk | 56822657 | `aad75b20b35e307d6cfd172b8bd2089a4205c75ae61ab04aff2e37927dfa67ae` | com.qsw.rdesk、2.3.2/25、应用名「随控」；签名证书 SHA-256 `25e3843e…a9212` 与线上旧版相同 |

- 改名前的预览构建另外验证：Windows exe 文件说明/产品名为「随控」、公司 QSW；本机签名安装的 Mac 在访达显示「随控」（Info.plist 基础名保持 rdesk，本地化 InfoPlist.strings 提供随控）；APK 应用名为「随控」。
- 托盘/单实例：在虚拟机系统会话中确认 `--hidden` 启动常驻、再次启动只保留一个实例；自启动 PowerShell 读写（含「启动应用」禁用标记）在虚拟机实测正确。
- Flutter：`flutter analyze` 无问题，完整 `flutter test` 162 项通过（一次全量运行出现 1 项偶发失败，重跑两次均全部通过）。
- 用应用自身 `UpdateRelease.fromManifest` 读取新清单：macOS arm64/x64、Windows、Android 均解析为 2.3.2，地址、字节数和说明正确。

## 官网

- 本地 `prepare_website.py`、`package_website.py` 校验 5 个安装包后打包（成品 SHA-256 `d5cdd2d1…e59eee6`）；上传 `rdesk-new` 后摘要一致，解压到 `/opt/rdesk-website/releases/20260929-2.3.2`，`MANIFEST.sha256` 校验通过；复制历次安装包，属主 root，原子切换 `current`。上一版 `releases/20260928-2.3.1` 保留，可切回软链接回滚。
- 公网：首页（标题「随控远程官网」）、下载页、支持页、隐私页 200；`releases.json` 与本地逐字节一致；5 个新文件 Content-Length、Range 206、完整下载 SHA-256 全部一致；下载回来的 DMG `stapler validate` 通过；2.3.1、2.3.0、2.2.3 旧链接 200；`/go/rdesk` 仍跳转官网。

## 发布后 Windows 桌面验证（2026-09-30）

在 Parallels Windows 11 的交互用户会话中，用 UI 自动化（只向安装器按钮发送点击消息，用 PrintWindow 截取本程序窗口）完成：

- 先静默安装 2.3.1（带桌面快捷方式）并写入旧格式开机自启 `"…\rdesk.exe"`；再交互运行公开的 2.3.2 安装包：欢迎页、选项页、完成页均为中文与品牌侧栏；因已开启自启，选项页自动预选「开机后自动启动随控」；升级跳过位置页，选项页的「下一步」直接开始安装。
- 升级后：程序为 2.3.2+25、文件说明「随控」；开始菜单 `RDesk\RDesk.lnk` 与桌面 `RDesk.lnk` 被删除，换为 `随控\随控.lnk` 与桌面 `随控.lnk`；Run 值升级为 `"…\rdesk.exe" --hidden`；完成页勾选的「打开」启动了窗口标题为「随控」的主界面。
- 向主窗口发送 WM_CLOSE：窗口隐藏、进程保留；再次运行 exe：原窗口重新显示，始终 1 个进程。`--hidden` 启动：进程常驻、窗口不显示；Windows 通知区域登记了该程序图标（提示文字「随控」，按 Windows 11 默认收在折叠区）；再次运行 exe 时窗口弹出，仍 1 个进程。
- 静默卸载：程序、快捷方式与 Run 值全部移除。
- 发现并修正（未重新发布）：中文文案在应用名两侧多了空格（如「欢迎安装 随控」「安装 随控」），源码已改为「欢迎安装随控」等，重新编译确认；随下个版本发布。
- 首次测试时 `--hidden` 启动显示 0 个进程，原因是脚本强制结束旧进程后立即启动，旧进程尚未退出而触发单实例退出；等待旧进程退出后复测正常。

## 未覆盖

- 托盘右键菜单、首次隐藏气泡提示没有通过真实鼠标操作查看；应用内更新的下载与安装交接未实际点击验证；Windows 安装包仍无发布者签名。
- 单独托管的 App Store 支持页 `qsw745.github.io/rdesk-support` 未改名。
- 物理网络唤醒（睡眠、关机、隔夜、24/48 小时）仍待实测。
