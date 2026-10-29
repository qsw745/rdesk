# 2.3.12（35）发布验证（2026-10-29）

## 范围

应用源码基线 `f9612e6`，主要功能提交 `e165576`：普通设置移除服务器地址编辑，官方账号/中继使用集中 HTTPS 配置，旧来源账号、生物识别、可信设备密码（含孤儿键）迁移隔离，写入失败与并发迁移阻止跨来源请求。沿用已有桌面输入、多显示器与文件传输实现。本轮未更改 API 或共享 nginx 入口。

## 本地验证

- 上一轮完整 Flutter 测试 367 通过、1 按平台跳过；本轮重新执行网络策略和应用更新切片，36 项通过。
- 所有编译、打包在本机或本机 Parallels Windows 11 内完成，没有服务器/云 CI 构建。
- Mac Apple 芯片版：Developer ID 签名、Hardened Runtime、全包原生库架构扫描、应用公证与装订、DMG 公证与装订通过。全包最高最低系统版本为 macOS 13（`objective_c.framework`）；不能只按主 App 的 macOS 12 声明判断。
- Windows x64：从基线提交导出的 ZIP 在本地 VM 内展开，运行 `scripts/build_windows.ps1`；PE 架构、进程启动、静默安装及安装后主程序摘要检查通过；取回本机的两份成品摘要与 VM 一致。沿用未签名安装包方案。

- Android：`flutter build apk --release --no-pub` 成功，包名 `com.qsw.rdesk`、2.3.12（35）、最低 API 24，包含 arm64-v8a/armeabi-v7a/x86_64；APK 校验通过，签名证书 SHA-256 与公开 2.3.2 一致。未连接 Android 实体手机，未声称真机安装通过。

- Mac Intel 版：应用公证与装订通过；最终 DMG 挂载后的 Apple 芯片 App、最终 ZIP 解包后的 Intel App 均再次通过全包架构、Developer ID/Hardened Runtime 签名和装订票据验证（各 13 个 Mach-O）。两种架构最终成品的最高原生最低系统均为 macOS 13。
- 使用产品实际的 `UpdateRelease.fromManifest` 解析本轮清单，Mac arm64/x64、Windows、Android 均得到 2.3.12（35），并能正确判为高于 2.3.11（34）；iOS 继续指向商店 2.3.2。

## 成品

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| RDesk-2.3.12-windows-x64-setup.exe | 13332378 | `78fdecb3ef76bbebb68d708af04dc623a61340fbf0c9f4becbdd508d9d00b679` |
| RDesk-2.3.12-windows-x64-portable.zip | 14459866 | `59c6a710862bf700d617a30042038deb0b5ff838422bedddfdf003f452c8ea61` |
| RDesk-2.3.12-android.apk | 57069581 | `734730a71d8c474b4a5a064ed351d5b4e61161732ddbc8c7a7b31c298b031fce` |
| RDesk-2.3.12-macos-arm64.dmg | 17051429 | `b4ded02b48667d42562484bd1fea1fd437fe020036d16a395083817d5a6a5abf` |
| RDesk-2.3.12-macos-x64.zip | 16671980 | `5e014c0a5e1d770661ba3f083e3c48220dc3db060a936fdbcca0381824c9598e` |

公证 ID：Apple 芯片 App `5647d6cc-d5d2-4732-8f6d-298ca15f51a0`，DMG `d89293b9-9233-4022-9404-83181142a11b`，Intel App `009a280d-be7f-41cd-b8fa-3a6e2a5f7d0f`，均为 Accepted。

## iOS 状态

ASC 与中国区公开查询均确认 2.3.2 已上架（公开最低系统 iOS 15）。官网旧的 2.1.0 文案将按当前状态修正。用户本轮明确选择「先发布官网三端，iOS 暂停送审」。没有上传或提交 iOS 2.3.12；审核演示手机当前未连接、检查所需环境变量未配置，不能将本机 iPhone 的安装成功当作演示被控端就绪。

## 官网与更新清单

- 成品包 SHA-256：`f2172283777f6d095e2a2834ba8be52c4eb36a18e50f3244bad2f9941f96dbdb`，只上传本地预构建成品。远端校验压缩包与全部 MANIFEST 文件后切换 `current -> releases/20261029-2.3.12`；`PREVIOUS_RELEASE` 为 `releases/20261029-download-layout`。
- 新目录保留上一版清单内的五个安装包，覆盖客户端清单缓存最长 6 小时的过渡；当前版和回滚版中的旧文件均重新核对摘要一致。只保留 `20261029-2.3.12` 与 `20261029-download-layout` 两个版本目录。
- 公网首页、下载页及 `releases.json` 与本地成品逐字节一致。实际页面显示 Mac/Windows/Android 2.3.12，iOS 2.3.2（最低 iOS 15）；四个主按钮仍对齐，无横向溢出。
- 五个新文件的公网 HEAD 长度、Range 206 与首段字节、完整下载长度及 SHA-256 均通过。下载较慢时使用断点续传，完整文件最终摘要均与本地发行成品一致。
- 本机 Mac 实际界面的「检查更新」成功完成，由「高于公开版本 2.3.5」变为「当前已是最新版本」，本机版本为 2.3.12（35）。
- 本轮没有上传或提交 iOS 新版，没有部署 API、重载共享入口 nginx，也未触发云构建。

## 未覆盖

没有真实 Intel Mac 运行验证；没有连接的 Android 实体测试手机。Windows 启动和安装验证不证明中文输入法转发、真实多屏输入或物理远程开机通过。本次没有对其他设备发送测试鼠标、键盘、电源或文件操作。
