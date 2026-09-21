# 家中局域网助手与开机诊断（实验版 0.1.0）

当前程序可用于允许运行自定义程序的 Linux 路由器、NAS 或常开 Linux 主机，补充现有安卓助手。**尚未在用户的 AX3000T 原厂 2.0.28 固件上安装或验证，不能把二进制上传到“插件安装”当作小米插件。** macOS 成品只用于读取账号诊断等管理操作，不能启动发包守护进程。手机安装包仍是 2.2.2，本轮没有宣称增加手机内的路由器一键安装入口。

## 开机链路

手机或电脑在 RDesk 点击开机 → HTTPS 服务器 → 家中助手主动领取 → 在指定 LAN 发三次 UDP 9 子网广播 → 有待机供电且正确配置的网卡唤醒电脑。无需家庭公网 IPv4、端口转发或路由器公网管理页面。

这条路径避免依赖关机电脑的动态 NAT/ARP 记录。它仍需要家中有能运行助手的常在线设备。路由器只是转发普通网络流量，并不自动等于能够接收 RDesk 账号指令和代发广播；需要已有兼容功能或安装权限。

UU 的公开开发者介绍确认支持路由器辅助开机，但本次未确认该用户实际的 UU 辅助设备、路由器集成版本或 UU 内部转发策略。局域网能开、外网不能开，说明当时硬件具备被本地唤醒的条件，排查应先看“外网到家中助手”这一段，再检查广播和网卡状态，不能仅凭现象认定唯一原因。

## 本地构建

需要本机 Go 1.24 或以上，只有标准库依赖。全部编译与测试在开发电脑执行：

```sh
sh tools/wake-helper/build-local.sh /绝对路径/wake-helper-output
```

输出 Linux amd64、arm64、armv7 和 macOS arm64、amd64 文件及 SHA256SUMS。Linux 文件不依赖 GLIBC，但仍需兼容的内核、架构、系统 CA 证书及运行权限；不保证低内存路由器的实测占用。服务器和路由器只接收预构建成品，不现场编译。

## 在已有程序运行权限的 Linux 设备配置

以下是适配设备的操作指南，本次未自动执行到用户路由器。先确认 `uname -m`、可用空间、LAN 接口及 CA 证书。缺少安装权限时停在此处；不需要为了本程序先降级、刷机或拆机。请选择主 LAN，不能是 WAN、访客网或 VPN 接口。

1. 上传匹配架构的二进制，校验 SHA256，安装为 `/usr/local/bin/rdesk-wake-helper`（OpenWrt 模板用 `/usr/bin/`），执行 `chmod 755`。
2. `rdesk-wake-helper interfaces` 查看可用接口。推荐助手使用固定 LAN 地址，或路由器 DHCP 静态租约。登记的是**助手设备本机**地址，不是被唤醒电脑地址。
3. 登记助手。账号密码通过管道传入，不写命令行、配置或日志。设备有 Python 时可在该设备执行下面的命令；没有 Python 时，在本地 Mac 使用同一个脚本，通过已配置好的 SSH 连接传送标准输入。

```sh
# 示例占位值必须换成实际 LAN 接口及助手地址；不要照抄到未知网络。
python3 tools/wake-helper/credentials.py | ssh -T root@助手局域网地址 \
  '/usr/bin/rdesk-wake-helper enroll --state /etc/rdesk-wake-helper --interface br-lan --cidr 192.168.31.1/24 --name 家中路由器'
```

如需 sudo，在登记前交互获取权限（`sudo -v`），不要让 sudo 的密码输入与账号 JSON 争用标准输入。SSH 身份验证应预先完成。只在家中局域网管理设备，不开放公网 SSH。

4. 在助手设备执行 `rdesk-wake-helper run --state /etc/rdesk-wake-helper`。绑定接口需要 root 或 CAP_NET_RAW。随后在 RDesk 的远程开机设置中刷新助手，选择登记的名称。现有 App 列表按账号读取助手，不要求名称包含安卓；部分引导文案仍按安卓显示，这是本实验版的已知界面边界。
5. 前台验证成功后，按设备系统选择随附 systemd 或 OpenWrt procd 模板。**上面命令是 OpenWrt 的路径示例**：程序 `/usr/bin/rdesk-wake-helper`、状态 `/etc/rdesk-wake-helper`，与 procd 模板一致。若使用 systemd，请在第 3、4 步就改用程序 `/usr/local/bin/rdesk-wake-helper` 和状态 `/var/lib/rdesk-wake-helper`，与 `.service` 模板一致。不能登记到一个目录后让后台服务读取另一个空目录。必须保留配置目录和 `journal.json`；不要在存在未完成请求时删除记录或并行使用同一助手凭据。

`config.json` 只存助手专用令牌和绑定的接口信息。整个目录权限 700、文件 600。令牌仅能领取该助手任务，不能读账号设备列表。移除或停用助手会撤销执行权限。不要共享配置目录；分享诊断只分享 `inspect` 或 `diagnose` 的输出。

systemd 设备的完整路径示例（`eth0`、地址仍须换成实际值）：

```sh
python3 tools/wake-helper/credentials.py | ssh -T root@助手局域网地址 \
  '/usr/local/bin/rdesk-wake-helper enroll --state /var/lib/rdesk-wake-helper --interface eth0 --cidr 192.168.31.20/24 --name 家中Linux助手'
# 以下在助手上执行；先上传随附 .service 模板到 /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now rdesk-wake-helper
/usr/local/bin/rdesk-wake-helper inspect --state /var/lib/rdesk-wake-helper
```

OpenWrt 设备在前述 `/etc/rdesk-wake-helper` 登记后，把随附 procd 文件安装到 `/etc/init.d/rdesk-wake-helper`，权限 755，再执行 `/etc/init.d/rdesk-wake-helper enable` 和 `/etc/init.d/rdesk-wake-helper start`。模板每 30 秒重试启动且不耗尽次数，每次仍核对登记的 LAN。手动 stop 会停止托管。systemd/procd 模板尚待真实目标设备启动验收。

网络接口、IPv4/掩码或硬件地址变化时暂停发送，避免在错误网络广播。确定新网络后停用旧助手，用新目录重新登记并重新选择。仅 WAN 断线、LAN 未变化时，运行中的助手会自动退避重连。systemd/procd 在重启后拉起；没有配置服务管理器时，退出终端或设备重启不会自动启动。

## 查看诊断

在助手上查看最近最多 200 条本地事件，不需要账号密码，不发送唤醒包：

```sh
rdesk-wake-helper inspect --state /etc/rdesk-wake-helper
```

在 Mac 或其他管理电脑读取账号下电脑的开机时间线（只读，不发送开机请求）：

先把相应平台成品重命名为 `rdesk-wake-helper` 并赋予执行权限。例如 Apple Silicon Mac 用 `rdesk-wake-helper-0.1.0-darwin-arm64`，Intel Mac 用 `darwin-amd64`；这是本地编译的实验命令行工具，不是已公证的 App 安装器。

```sh
umask 077
python3 tools/wake-helper/credentials.py | ./rdesk-wake-helper diagnose > 开机诊断.txt
# 可附加 --target 配置ID，仅看某台电脑。
```

`diagnose` 会为这次登录建立普通账号会话，但不持久保存账号令牌。报告含电脑名称、请求标识和时间，不含密码、令牌、MAC 和局域网地址。请不要分享原始 `config.json`。

| 最后证据 | 能说明什么 | 下一步 |
| --- | --- | --- |
| queued | 服务器收到了请求，尚无助手领取 | 看助手在线状态、家庭联网和守护进程 |
| claimed / authorized | 助手领取或获得短时发送许可 | 对照请求 ID 找本地日志 |
| packet_written | 本地操作系统接受一个 UDP 包 | 不是网卡收到包的证明 |
| sent | 助手完成三次发送，等待或已提交回执 | 检查实际供电、BIOS、网卡，等待应用心跳 |
| receipt_accepted | 服务器接受了执行结果，可能是成功也可能是失败 | 看 `code=sent/failed` 和包数，不能一概当作发包成功 |
| unconfirmed | 120 秒内无新应用心跳 | 可能已启动但没登录 Windows；不能直接判断硬件没开 |
| online | 请求后收到新的 RDesk 应用心跳 | 若人为开机或原本在线，也不能证明 WOL 因果 |
| execution_uncertain | 进程中断，无法确认发包完成情况 | 不自动重发旧请求，检查现场再重新点击 |

本地日志两个文件合计约 512 KiB，按大小轮换；健康记录每 5 分钟写一次，网络错误按退避频率记录。日志无法写入时输出 `log_write_failed`，可从服务 stderr 查看；去重状态写入失败会停止执行。OpenWrt 的 `/etc` 通常位于闪存，当前日志有持续的小量写入，尚未做实机闪存寿命/资源测试；实验运行先关注空间与写入情况，不承诺任意低端路由器都适合长期部署。去重状态最多 2048 条，已处理记录保留七天，到达上限时拒绝新执行。服务器已有的账号记录保留七天、最多 50 条。日志不能还原没有被设备观测到的物理链路。

## 实机验收（仍待完成）

1. 先保持电脑开机，确认助手在线和网卡/BIOS 配置；不在有未保存工作时自动睡眠/关机。
2. 用户主动睡眠后，在手机关闭 Wi-Fi、使用蜂窝网络发起，保存请求 ID 和日志；观察实际电源、启动与登录阶段。
3. 在硬件支持的情况下，再分别测试关机、助手锁屏或设备重启、WAN 断网恢复、隔夜、24 小时、48 小时。
4. 每次分别记“服务器接受”“助手领取”“发包”“物理开机”“应用上线”，不要把某一步成功写成全链路通过。

若原厂 AX3000T 不能运行助手，已有安卓方案仍可用；可兼容的 NAS/常开 Linux 设备也是备选。不能凭本地测试承诺这台原厂路由器可直接安装。
