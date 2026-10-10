# Windows 2.3.6 发布记录（2026-10-10）

## 内容

- 源码：提交 `92d76a5`（版本 2.3.6+29）。相对上一个公开的 Windows 版本 2.3.2，主要变化是 Windows 电脑可以被远程查看和控制（`d0b5fbc`，设计与验证范围见 `docs/design/2026-10-10-windows-host.md`），默认关闭，需在电脑上手动打开「允许远程控制本机」。
- 只发布 Windows。macOS 仍为 2.3.5（28），Android 仍为 2.3.2（25），iOS 商店仍为 2.1.0。这三个公开版本的设备列表把所有 Windows 电脑显示为不可被控，要在设备列表里直接连接 Windows 需要控制端也更新；官网下载页、支持页和应用内更新说明都写明了这一点。
- 配套服务端字段已于同日先行部署，见 `docs/validation/server-deploy-2026-10-10.md`。

## 构建

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| RDesk-2.3.6-windows-x64-setup.exe | 13206936 | `8e8f74de9d82f00dfd0322cd8929df9fd0124ba651b269348f06cb14308dd806` |
| RDesk-2.3.6-windows-x64-portable.zip | 14262598 | `e46ee01a7593fc85f0d80cad50bde89541b63fbe66aa22d673e59aa9364a4f41` |

- 本地 Parallels Windows 11 + VS2022，`git archive` 导出 `92d76a5` 到 `C:\dev\rdesk-2.3.6` 后运行 `scripts\build_windows.ps1`：`/W4 /WX` 无警告，x64、启动与静默安装检查通过；构建后虚拟机恢复挂起。导出包里的 `scripts/检测远程开机.cmd` 因文件名编码在虚拟机中解压失败，该文件不参与构建和安装包。
- 2.3.6 与当天在虚拟机里做过采集、输入和端到端验证的构建相比，源码只多了版本号和对外文案；发布构建本身没有重跑那套原生与端到端检查。
- `flutter analyze` 无问题；新增 `test/published_manifest_test.dart`，用应用自身的 `UpdateRelease.fromManifest` 读取仓库里的清单：Windows 解析为 2.3.6 且高于 2.3.2（25），macOS arm64/x64、Android 仍可解析。
- 安装包没有发布者签名，已决定暂不签名。

## 官网

- 本地 `prepare_website.py`、`package_website.py` 校验 5 个安装包后打包（成品 SHA-256 `b01153eb…e4087ff0`）；上传 `rdesk-new` 后摘要一致，解压到 `/opt/rdesk-website/releases/20261010-2.3.6`，`MANIFEST.sha256` 校验通过；补齐历次安装包（与上一版目录比对无缺失），属主 root，原子切换 `current`。上一版 `releases/20261009-2.3.5` 保留，可切回软链接回滚。
- 公网：首页、下载页、支持页、隐私页 200；下载页指向 2.3.6；支持页出现「让 Windows 电脑被远程控制」一节；`releases.json` 与本地逐字节一致；两个新文件 Content-Length、Range 206、完整下载 SHA-256 一致；2.3.2 Windows、2.3.5 Mac、2.3.2 Android、2.2.3 旧链接仍为 200。
- 在虚拟机的登录用户会话中从公网下载安装包：摘要一致，静默安装退出码 0，安装后版本 2.3.6+29；`--hidden` 启动后进程常驻，21116 端口未监听（被控关闭）。之后已卸载。虚拟机里此前没有安装随控，所以这是全新安装，不是从 2.3.2 覆盖升级。

## 回滚

```sh
# rdesk-new
cd /opt/rdesk-website && sudo ln -s releases/20261009-2.3.5 current.next && sudo mv -Tf current.next current
```

回滚后清单回到 Windows 2.3.2。已经升级到 2.3.6 的电脑不会被降级。

## 未覆盖

- 应用内更新从 2.3.2 到 2.3.6 的提示、下载、校验与安装交接没有实际点击验证；从 2.3.2 覆盖升级后设置与远程开机配置是否保留也没有实测。
- 被控功能没有在实体 Windows 电脑上、经公网中继、由真实的 Mac 或手机控制端连接验证过；多显示器、非 100% 缩放、锁屏与 UAC、管理员窗口输入拦截、托盘菜单两项的实际点击同样未验证。详见设计文档的「尚未验证」。
- 被控密码认证没有失败限速，临时验证码只有 6 位且长期有效；修复在另一项工作中进行，未包含在本版本。
- 单独托管的 App Store 支持页 `qsw745.github.io/rdesk-support` 未更新。
