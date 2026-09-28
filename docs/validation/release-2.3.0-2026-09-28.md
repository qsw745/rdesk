# 2.3.0 发布记录（2026-09-28）

## 内容

- 源码：提交 `e6e24f3`（版本 2.3.0+23）。包含对标 UU 远程的界面重做、远程开机简化（Windows 一个开关、自动选择家中助手、无扫码配对）、助手断网自动恢复、Mac 助手自动恢复与登录项、新应用图标。
- 服务端无需改动：远程开机沿用已部署的 `/api/wake/` 接口（直接登记与更换助手接口此前已存在）。

## 构建（全部在本机或本机虚拟机完成）

| 文件 | 字节 | SHA-256 | 验证 |
| --- | --- | --- | --- |
| RDesk-2.3.0-macos-arm64.dmg | 16838943 | `9592815c881f0bb32cba72b9806a134f0fe879efd9cb8f87afcd9f6994439142` | 应用与 DMG 分别公证 Accepted 并装订；`spctl` 为 Notarized Developer ID |
| RDesk-2.3.0-macos-x64.zip | 16430731 | `7b3a2a54c99122ecb2ee8a1a26995d1fec6a4855faec68cf8cc7152c2ff77828` | 主程序为 x86_64；公证 Accepted 并装订 |
| RDesk-2.3.0-windows-x64-setup.exe | 12235052 | `2f9ae741111b1f72358121ad8fc9e779530638bfddf464c15741b3767b668152` | 本地 Parallels Windows 11 + VS2022：x64 PE、启动 8 秒存活、静默安装后主程序摘要一致 |
| RDesk-2.3.0-windows-x64-portable.zip | 14195736 | `a23e671442d44f19dd02fcfb7936bf458405cf68570f4e281a35db7e4e9cb5fd` | 同上构建产物 |
| RDesk-2.3.0-android.apk | 56789741 | `d08447c0e6eccdd169e8fcdfcfdef112893c03c77737e5139461cc3ba41690f0` | 包名 com.qsw.rdesk、2.3.0/23；签名证书 SHA-256 `25e3843e…a9212` 与线上 2.2.3 相同，可覆盖升级 |

- Mac 两个架构用新脚本 `scripts/release_macos.sh arm64|x86_64` 构建：独立 derivedData、内嵌并签名双架构开机助手、Developer ID 签名、公证、装订；DMG 内附「应用程序」快捷方式。
- Windows 源码为 `git archive HEAD` 导出后在虚拟机本地盘解压构建，不在共享盘上编译；构建后虚拟机恢复挂起。
- 用应用自身的 `UpdateRelease.fromManifest` 读取新 `releases.json`：macOS arm64/x64、Windows、Android 均解析成功，版本高于 2.2.3（20），地址、字节数与摘要正确。

## 官网

- 发布清单更新为 2.3.0；官网模板的远程开机介绍改为新的三步（家中助手开关 → Windows「允许远程开机」→ 外出点「开机」），主色换为新品牌蓝、开机步骤用橙色；常见问题补充 iOS 新版需要 15。支持页的快速开始、远程开机、忘记密码、注销账号改为新界面名称，并注明 App Store 2.1.0 仍为旧界面。
- 本地 `package_website.py` 校验 5 个安装包后打包；上传至 `124.223.200.182`（rdesk-new），解压到 `/opt/rdesk-website/releases/20260928-2.3.0`，`MANIFEST.sha256` 校验通过，复制历次安装包以保留旧下载链接，属主 root，原子切换 `current`。上一版 `releases/20260921-2.2.3` 保留，可切回软链接回滚。
- 公网验证：首页、下载页、支持页（301 到带斜杠地址）、隐私页正常；`releases.json` 与本地逐字节一致；5 个新文件的 Content-Length、Range 206 与完整下载 SHA-256 全部一致；下载回来的 DMG `stapler validate` 通过；旧版 2.2.3、2.1.1 链接仍为 200；`/go/rdesk` 仍跳转到官网。

## 未覆盖

- 新 Windows「允许远程开机」流程只有单元测试与启动检查，没有在真实 Windows 电脑上走通开关、自动选助手和实际开机。
- 应用内更新的下载与安装交接没有在各平台实际点击验证；Windows 安装包仍无发布者签名。
- iOS 未构建上传，App Store 仍为 2.1.0；iOS 新版最低系统已改为 15，需要单独走上架流程。
- 物理网络唤醒（睡眠、关机、隔夜、24/48 小时）仍待实测。
