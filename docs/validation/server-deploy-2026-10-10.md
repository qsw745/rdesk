# 服务端部署：设备被控能力与托管状态（2026-10-10）

## 内容

- 源码：提交 `d0b5fbc`。相对线上此前运行的 `dbdc2e2`，服务端只多了 `a2aaaec`：登记可上报 `can_host`，账号设备列表返回 `can_host` 与 `hosting`。
- 构建：本机 `cargo zigbuild -p rdesk_server --release --locked --target x86_64-unknown-linux-musl`，构建前 `touch` 了源码以排除旧产物。x86-64 静态链接 ELF，SHA-256 `b62019d65d07125d1310813e0ff990b98c8debc8dd003cb13fca6dbe0c3dad10`。服务器上没有编译。
- 兼容：两个字段都是新增。旧客户端不上报 `can_host`，按 `false` 处理；旧客户端读取设备列表时忽略多出的字段。没有新增对外路由，公网入口 nginx 未改。

## 上线前检查

- 上传后服务器端摘要校验一致。
- 用线上数据目录的副本，在 127.0.0.1 临时端口以 `timeout` 前台方式试跑：健康检查正常，未登录读取设备列表返回 401，日志无 WARN/ERROR。试跑后的用户文件按 `user_id` 对齐与线上 10 个用户完全一致。试跑进程、端口和临时目录已确认清理。

## 部署

- 备份：`/var/backups/rdesk-server/20261010-predeploy-d0b5fbc/`（旧二进制、systemd unit、停服后的数据目录快照），另存 `/usr/local/bin/rdesk-server.bak-20261010`。
- 停服务 → 快照数据 → `mv` 原子替换 → 启动，停机约 0.06 秒。

## 上线后验证

- 本地与公网 `/health` 正常；重启后在线的被控端自动重新登记（`preview_count` 回到 2）；部署后日志没有 WARN/ERROR。
- `python3 scripts/check_account_capabilities.py --base https://qisw.top`（本次新增）6 步通过：未登录 401；上报能力未托管；旧客户端不具备能力；旧客户端登记为主机也不算具备能力；登记后托管中；注销后未托管。临时主机已注销，临时账号已删除。
- `python3 scripts/check_capture_on_demand.py --base https://qisw.top` 与 `python3 scripts/check_wake_pairing.py --base https://qisw.top` 通过，临时主机与账号已清理。
- 没有审核凭据，也没有连接 adb，因此没有运行 `scripts/check_review_host.sh`。

## 回滚

```sh
systemctl stop rdesk-server
cp -p /usr/local/bin/rdesk-server.bak-20261010 /usr/local/bin/rdesk-server
# 如需恢复数据，用 /var/backups/rdesk-server/20261010-predeploy-d0b5fbc/data
systemctl start rdesk-server
```

旧服务端不返回这两个字段。新版客户端在旧服务端上会把所有 Windows 账号设备显示为「版本较旧，更新后才能被远程控制」，不会出现无法执行的连接按钮。

## 未覆盖

- 上述冒烟只验证服务端协议。没有用真实的 Windows 被控端经公网中继登记、被查看或被控制。
- 支持被控的 Windows 客户端尚未发布，官网 Windows 安装包仍为 2.3.2。
