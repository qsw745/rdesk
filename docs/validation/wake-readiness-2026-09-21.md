# 无安卓依赖开机：硬件核查与只读工具

## 当前用户设备证据

- 用户路由器底标为 AX3000T / RD03。2026-09-21 Chrome 后台复核系统为稳定版 2.0.28；没有根据名称推断具体芯片，也没有读取、存储浏览器令牌。
- 对后台对应 LAN 地址的 TCP 22 单次只读连接被拒绝：当前没有可用 SSH 登录入口。没有扫描其他主机，没有尝试漏洞、刷机、降级、修改端口或安装插件。
- 用户 Windows 截图为 i5-14600KF、Windows 11。整机名称仅显示通用占位 `System Product Name`，不能据此判断主板或带外管理能力。报告和文档不保存截图中的设备/产品标识符。
- [Intel 的 i5-14600KF 规格](https://www.intel.cn/content/www/cn/zh/products/sku/236778/intel-core-i5-processor-14600kf-24m-cache-up-to-5-30-ghz/specifications.html)列出 ISM=Yes；同页说明特性取决于整个平台。[Intel ISM/AMT 对比](https://www.intel.com/content/www/us/en/support/articles/000090499/technologies/intel-active-management-technology-intel-amt.html)区分两者，Fast Call for Help 仅在 AMT 列勾选。不能由 CPU 这一项宣称已支持 CIRA 外网开机。
- [Intel AMT 开发说明](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-vpro-manageability-software-integration.html)说明受支持平台可以通过不依赖 OS 的管理与主动连接路径进行电源操作。但用户整机是否具备这一路径仍待查主板及固件。

## 本轮实现

`scripts/collect-wake-readiness.ps1` 和同目录 `检测远程开机.cmd`：在 Windows 本地读取主板、CPU、整机产品、系统版本、物理网卡、驱动魔术包/关机唤醒选项、系统已授权唤醒状态、快速启动和可用电源状态。无下载、上传或网络探测；仅在指定新目录保存 JSON 和中文文本。

报告采用字段白名单，不包含主机名、用户名、序列号、UUID、产品密钥、MAC、IP。读取失败保持 unknown/unavailable，不把虚拟机检测或 CPU 品牌等同于硬件支持。关机驱动字段也不能替代实际 S5 唤醒验收。快速启动仅报告注册表配置，实际生效状态保持未验证；powercfg 的本地化名称未匹配时也保持 unknown。

CMD 的 `-ExecutionPolicy Bypass` 仅作用于此次 PowerShell 进程，不更改机器执行策略。脚本不修改网卡、注册表、服务、电源或 BIOS，不重启、不发送 WOL。

## 本地验证

- 本地 Windows 11 虚拟机 PowerShell 测试通过：硬件与网卡白名单、空数据、unknown 状态、禁用状态、厂商未知值、不能虚构 AMT 能力。
- 实际 VM 采集成功，得到两个可解析 UTF-8 报告；主板、CPU、系统和一块物理标记的虚拟网卡查询成功，无 unavailable 项。此证据来自虚拟机，不是用户实际 Windows 主机。
- 源 PS1 使用 UTF-8 BOM，兼容 Windows PowerShell 5.1；交付 CMD 使用 CRLF。报告文件不加入 Git。
- 原工作区其余未提交改动保持不动；没有重编手机或 Windows App，也没有变更当前公开 2.2.2 安装包。

## 用户操作

解压检测工具压缩包，在需要远程开机的那台 Windows 上双击 `检测远程开机.cmd`。无需管理员提权。桌面生成 `RDesk-Wake-Check-时间-随机后缀`，其中 `检测结果.txt` 可直接查看主板型号与网卡状态。

此工具仅帮助选择后续方案，不是已交付的无助手开机功能。若原厂路由器不能接入且整机没有可用带外管理，需要改变部署条件（兼容常在线硬件/路由器）；不能仅靠增加 Windows 关机后不会运行的软件实现外网可靠唤醒。
