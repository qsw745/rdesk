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

---

# 当日第二次部署：文件中转可被被控端取回

## 内容

- 源码：提交 `0e0d62a`。相对上午部署的 `d0b5fbc`，服务端改动是文件中转：观看者上传后，中转向被控端下发 `file_receive`，被控端用自己的主机凭据取回一次（新路由 `GET /api/file/host/download/:file_id`），再回报是否保存；上传接口据此返回 `{ok, saved_as}`。单个文件上限 50 MiB，中转内存合计上限 150 MiB，被拒收、超时或已取走的文件立即从内存删除。
- 构建：本机 `cargo zigbuild -p rdesk_server --release --locked --target x86_64-unknown-linux-musl`，x86-64 静态链接 ELF，SHA-256 `5858ed99a972c1e0343f5f530ce8f6b03af6c0fc65d99cb62c66dfe2ff240377`。服务器上没有编译。
- 公网入口：`/api/file/` 在 80 与 443 两个 server 段原本就整段转发，新路由不需要改 nginx；443 段请求体上限 500m、读超时 600s，高于服务端的 50 MiB 与 50 秒等待。

## 上线前检查

- 上传后服务器端摘要校验一致。
- 用线上数据目录副本在 127.0.0.1 临时端口以 `timeout` 前台方式试跑：健康检查正常，未认证访问新路由与上传接口都返回 401，日志无 WARN/ERROR。试跑进程与临时目录已确认清理。

## 部署

- 备份：`/var/backups/rdesk-server/20261010-predeploy-0e0d62a/`（旧二进制、systemd unit、停服后的数据目录快照），另存 `/usr/local/bin/rdesk-server.bak-20261010b`。上午的 `rdesk-server.bak-20261010` 仍在。
- 停服务 → 快照数据 → `mv` 原子替换 → 启动，停机约 0.05 秒。

## 上线后验证

- 本地与公网 `/health` 正常，线上二进制摘要与本地一致；在线被控端自动重新登记（`preview_count` 回到 2）；部署后日志没有 panic 或 error。
- 公网未认证访问 `/api/file/host/download/…` 与 `/api/file/upload` 返回 401（不是 404，说明入口已转发）。
- `python3 scripts/check_file_relay.py --base https://qisw.top`（本次新增）通过：没有观看会话不能上传；模拟被控端收到 `file_receive`；`../../evil/报告 v2.bin` 只保留 `报告 v2.bin`；观看者凭据取不到文件；2 MiB 随机数据取回后 SHA-256 一致；同一文件第二次取回 404；回报保存后观看者得到 `ok` 与文件名；拒收后观看者得到未保存，文件已从中转删除。临时主机已注销。
- `check_account_capabilities.py`、`check_capture_on_demand.py`、`check_wake_pairing.py` 对公网重跑通过，临时主机与账号已清理。
- 没有审核凭据，也没有连接 adb，因此没有运行 `scripts/check_review_host.sh`。

## 回滚

```sh
systemctl stop rdesk-server
cp -p /usr/local/bin/rdesk-server.bak-20261010b /usr/local/bin/rdesk-server
systemctl start rdesk-server
```

回滚后的服务端没有被控端取回接口：新版客户端发文件会得到失败提示，其余功能不受影响。

## 未覆盖

- 冒烟只验证服务端协议，没有真实电脑经公网中继把文件写入磁盘。
- 没有在公网测试 50 MiB 上限、150 MiB 合计上限和 50 秒等待超时，这三项只由 `cargo test -p rdesk_server` 覆盖。

---

# 当日第三次部署：文件中转先认证再读请求体

## 起因

第二次部署后做的安全审查发现，`0e0d62a` 的上传接口用 axum 的 `Bytes` 提取请求体：框架会先把最多 50 MiB 的请求体读进内存，再进入处理函数校验观看会话。未登录的并发请求因此可以占满服务器内存（服务器内存 1.9 GB）。合计额度的检查与写入也不是一步，且只统计已收完的文件，挡不住这种情况。

带问题的版本在线上运行了约 22 分钟（13:17:36–13:39:22）。当天 13:00 之后的 7 条文件中转记录全部来自冒烟脚本，服务日志没有 panic 或 error，内核日志没有内存不足记录，没有发现被利用的迹象；但日志不记录被拒绝的请求，不能证明没有人试探过。

## 内容

- 源码：提交 `ca89a93`。
  - 先校验观看会话、文件名和 `Content-Length`，再读请求体；没有 `Content-Length` 返回 411，超过单文件上限返回 413。
  - 合计额度在准入时原子预占，请求结束时归还，并发上传不再能越过 150 MiB。
  - 请求结束（包括发送方断开、处理被取消）时立即删除暂存文件，不再等 5 分钟清理。
- 构建：本机 `cargo zigbuild`，x86-64 静态链接 ELF，SHA-256 `b2b4d202d1de7b4d3cd77f8cddd519816becc12b87f1603eeebc16d451dc36ba`，已核对二进制包含新的提示文字。服务器上没有编译。

## 验证

- `cargo test -p rdesk_server` 46 项通过，新增：未认证时不读请求体；必须声明大小且不超过上限；实际内容短于声明时拒绝并归还额度；额度从准入起计；发送方中途离开不留下文件；被控端只回报不取文件时也不保留。
- 本机对比（调试构建，6 个未认证的 45 MB 并发上传，均返回 401）：修复前 `0e0d62a` 常驻内存峰值 573 MB，修复后 10 MB。
- 部署：上传后摘要一致；线上数据副本试跑正常；备份 `/var/backups/rdesk-server/20261010-predeploy-ca89a93/` 与 `/usr/local/bin/rdesk-server.bak-20261010c`；停机约 0.03 秒；试跑进程与临时目录已清理。
- 上线后：本地与公网 `/health` 正常，线上摘要与本地一致，被控端自动重新登记（`preview_count` 回到 2），日志无 panic 或 error。
- 公网：4 个未认证的 30 MB 并发上传，每个只发出约 0.8 MB 就被拒绝（0.07 秒），服务进程常驻内存 4552 KB → 4600 KB。其中 3 个得到 401，1 个得到入口 nginx 的 502：服务端不读请求体就应答并关闭连接，nginx 还在转发请求体时写入失败。
- `check_file_relay.py`（18 步）、`check_account_capabilities.py`、`check_capture_on_demand.py`、`check_wake_pairing.py` 对公网重跑通过。

## 回滚

不要回滚到 `rdesk-server.bak-20261010c`（即带问题的 `0e0d62a`）。需要回滚时用上午的 `rdesk-server.bak-20261010b`（`d0b5fbc`，没有被控端取回接口，新版客户端发文件会得到失败提示）。

## 未覆盖与已知行为

- 被拒绝的大请求在公网可能表现为 502 或连接中断而不是原始状态码。对正常客户端的影响：中转空间不足（507）时，较大的文件可能只显示笼统的「发送失败」，而不是「中转服务器暂时没有空间」。
- 有合法观看会话的人仍可用几台自己登记的被控端占住合计额度，每个请求最多占 50 秒；没有按来源限速。认证限速在另一项工作中处理。
- 没有在公网测试 50 MiB 与 150 MiB 上限和 50 秒等待超时。
