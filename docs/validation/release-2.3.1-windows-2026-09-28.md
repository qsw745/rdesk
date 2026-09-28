# Windows 2.3.1 发布记录（2026-09-28）

## 内容

- 源码：提交 `d815144`（版本 2.3.1+24），包含 `bdc5a3d`：
  - 「魔术包唤醒」检测：`Get-NetAdapterPowerManagement` 需要管理员权限，普通用户运行 RDesk 时一直显示「无法判断」；改为回退读取网卡高级属性 `*WakeOnMagicPacket`。已在本地 Windows 11 虚拟机以普通用户身份确认原命令报错、新脚本可运行，并用模拟属性确认 `1`/`0` 读取正确（虚拟机 VirtIO 网卡本身没有该属性）。
  - 家中助手离线时，远程开机页说明现在无法开机及处理办法。
- 只发布 Windows。macOS、Android 仍为 2.3.0（23），iOS 2.3.0（23）已上传待提交；此后重新构建 iOS 会带上 2.3.1+24。

## 构建

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| RDesk-2.3.1-windows-x64-setup.exe | 12233252 | `30aaa3a0867f3d7dc85a346567767dd87a2849e9b2803384fad1f0d1940beb00` |
| RDesk-2.3.1-windows-x64-portable.zip | 14196114 | `1bbe4e2c64b6ffecbdfd1b76d978d3a0661208f06ff549b4aeee1d2c9bfc9257` |

- 本地 Parallels Windows 11 + VS2022，`git archive` 导出到 `C:\dev\rdesk-2.3.1` 后运行 `scripts\build_windows.ps1`：x64、启动与静默安装检查通过；构建后虚拟机恢复挂起。
- 用应用自身的 `UpdateRelease.fromManifest` 读取新清单：Windows 解析为 2.3.1 且高于 2.3.0（23）；macOS arm64/x64、Android 仍解析为 2.3.0，不会收到更新提示。

## 官网

- 上传至 `rdesk-new`，解压到 `/opt/rdesk-website/releases/20260928-2.3.1`，`MANIFEST.sha256` 校验通过，复制历次安装包，原子切换 `current`；上一版 `releases/20260928-2.3.0` 保留可回滚。
- 公网：首页、下载页 200，下载页指向 2.3.1；`releases.json` 与本地逐字节一致；两个新文件 Content-Length、Range 206、完整下载 SHA-256 一致；2.3.0 各平台与 2.2.3 旧链接仍为 200。

## 未覆盖

- 没有在带真实物理网卡的 Windows 电脑上看到新检测结果；应用内更新的下载与安装交接未实际点击验证；安装包仍无发布者签名。
- 物理网络唤醒（关机、睡眠、隔夜）仍待实测。
