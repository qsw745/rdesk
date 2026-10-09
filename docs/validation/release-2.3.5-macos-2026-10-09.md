# macOS 2.3.5 发布记录（2026-10-09）

## 结果和范围

用户明确授权“允许上传 Apple 公证并替换官网”后，发布随控 **2.3.5（28）** 的 Apple 芯片 DMG 与 Intel ZIP。应用源码为 `5e09d3e20f2c591907f37e7eb82bc917e4af4982`，包括 Mac 更新原生库架构修复、设备记录合并、开机状态刷新和开机前助手状态核验。

官网已原子切换到 `releases/20261009-2.3.5`。Windows、Android 的 2.3.2 平台元数据和三个安装包保持原值；iOS 元数据保持原值，本轮未操作 App Store Connect。未部署 API 服务。

## 本地成品与 Apple 公证

| 成品 | 字节 | SHA-256 |
| --- | ---: | --- |
| RDesk-2.3.5-macos-arm64.dmg | 16842722 | `55d67283832628eea0ca5acaa2164590deeb7aad8345bdcf949b0dd5194f614f` |
| RDesk-2.3.5-macos-x64.zip | 16440563 | `16ab6aef541b72d652a3eaebc82d8c8df47c302e2a56aca92ea1ce04b3e40d1b` |

- 两种架构均在本机串行构建；默认入口 `lib/main.dart` 与最终 AOT/原生文件摘要绑定一致。每份 App 的全部 12 个 Mach-O 文件包含对应架构，`objective_c.framework` 不再混入另一架构。
- 两份 App 均保持 `com.qsw.rdesk`、内部名称 `rdesk.app`、Developer ID `qi shiwei (6N5T3G6H33)`、Hardened Runtime 与嵌入开机助手；深度严格签名和架构验收通过。
- arm64 App 公证 `1369d323-bded-4969-989d-9260dac8bd16`、Intel App 公证 `64b52b4c-c2ab-421a-8709-f0a3dce59b5c`、arm64 DMG 公证 `0682d313-db0a-4692-acc6-e6bba10c3c1f` 均为 `Accepted`。两份 App 与 DMG 的装订票据验证通过。
- 最终 DMG 只读挂载及 Intel ZIP 临时解压后的独立验收通过；ZIP CRC、路径、包装根目录及检查后成品摘要均正确。
- 全包原生库的最高最低系统版本为 macOS 13.0，官网卡片与 FAQ 统一声明 **macOS 13 或更高版本**。App 的基础 `LSMinimumSystemVersion` 仍为 12.0，不能据此宣称兼容 macOS 12。

## 官网切换

- 本地生成页面并打包整站，归档 `rdesk-website-20261009-2.3.5.tar.gz` 为 85,623,202 字节，SHA-256 为 `ed7e15fac72142b6ad25c710ce859a8cd5430f2bf600ed0843a50d4c5bb51226`；14 个归档成员路径安全，`MANIFEST.sha256` 的全部文件通过校验。
- 修正打包器的文件时间：每个归档成员使用同一发行时间，避免默认 1970 年时间使浏览器以 `If-Modified-Since` 错误保留旧页面。下载页 FAQ 的 Mac 系统要求改为读取平台元数据，避免与下载卡片不一致。
- 只上传预构建整站成品，服务器未编译、打包或安装构建依赖。切换前以部署锁、旧软链接和旧清单 SHA 校验防止覆盖并发变更。
- 服务端归档 SHA、解包后的 MANIFEST 和新清单 SHA 均正确；复制历史 `RDesk-*` 成品且不覆盖新版，随后原子替换 `current`。
- 新清单 SHA-256：`079d817d4742b2e7028887e40910022666c9a025cd2b04809904208753132760`。上一版 `releases/20260929-2.3.2` 保留，`PREVIOUS_RELEASE` 记录回滚目标。

## 验证

- 更新故障修复的测试、签名、本机安装与原生缓存/下载验证见 [前一阶段记录](macos-update-architecture-2026-10-09.md)。
- 本轮以真实 `UpdateRelease.fromManifest` 解析最终清单的契约检查通过：Mac arm64/x64 为 2.3.5（28），Windows/Android 为 2.3.2，iOS 保持 2.1.0。
- 发布后本机 2.3.5（28）应用点击“检查更新”，最终 UI 为“当前已是最新版本”。
- 两份新 Mac 成品从公开 HTTPS 地址完整下载，均为 HTTP 200、零重定向；实际字节数和 SHA-256 与上表及最终公证成品完全一致。
- 独立公网验收 67/67 检查通过：清单与本地逐字节一致；首页、下载页、JSON 的旧缓存条件请求返回 200；新包 HEAD 长度和 1 KiB Range 206 正确；14 条历史 Mac URL 返回 200，原长度保持不变；全部请求验证 TLS、零重定向。
- 非 Mac 平台条目及三个文件的字节数、摘要与部署前基线一致，公开 `SHA256SUMS.txt` 与最终清单一致；非 Mac 公开实体未重复完整下载，源站解包时已通过 MANIFEST 摘要校验。
- 现有公网 `/health` 返回 HTTP 200 和 `ok: true`。Python 语法、生成清单一致性和 `git diff --check` 通过；仓库没有会被推送触发的工作流文件。

本机发布证据保存在 `.release-work/macos-2.3.5/`，包括公证结果、最终成品检查、整站摘要与部署日志。

## 未覆盖

- Intel 成品完成交叉构建、全包架构、签名、公证和包装验收，未在真实 Intel Mac 上运行。
- 本机 `spctl` 识别为 `Notarized Developer ID`，但该机器已有 `override=security disabled`；本轮没有修改安全设置，不能把此结果视为全新 Mac 的 Gatekeeper 安装验收。Apple 公证 `Accepted` 与装订验证另有独立证据。
- 未在旧版本用户机器上完整点击升级安装；旧包原生库架构错误时，仍需从官网下载替换一次。
- 本轮未重复远程开机硬件验收，也不据发布成功推断隔夜、24 小时或 48 小时唤醒能力。
