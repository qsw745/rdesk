# 服务端部署：macOS 按需采集协议（2026-09-28）

## 内容

- 源码：提交 `dbdc2e2`（含 `a3063ce` 按需采集服务端协议）。线上此前运行的版本已包含开机配对（`3b6742b`），本次新增的只有按需采集。
- 构建：本机 `cargo zigbuild -p rdesk_server --release --locked --target x86_64-unknown-linux-musl`，x86-64 静态链接 ELF，SHA-256 `6fcd434d0a376edeee5d2bfcc63be8e055a5f3075785f38417e2784671aebea4`。强制重新编译后摘要不变，确认不是缓存的旧产物。服务器上没有编译。
- 兼容：只有注册时声明 `on_demand_capture` 的主机受“无观看拒绝上传（409）”约束；旧版 Mac、Android 被控端不声明，继续持续上传。

## 上线前检查

- 上传后服务器端摘要校验一致。
- 用线上用户数据的副本，在 127.0.0.1 临时端口试跑新版本：健康检查正常，新接口存在，日志无错误。新版本启动时会重写用户文件，但按 `user_id` 对齐后 9 个用户及其开机配置内容完全一致，只是 JSON 数组顺序不同。
- 试跑期间一次 `kill` 只结束了外层子 shell，留下两个只监听 127.0.0.1、使用临时副本的试跑进程；已全部结束并删除临时目录，正式服务不受影响。之后改用 `timeout` 前台运行。

## 部署

- 备份：`/var/backups/rdesk-server/20260928-predeploy-dbdc2e2/`（旧二进制、systemd unit、停服后的数据目录快照），另存 `/usr/local/bin/rdesk-server.bak-20260928`。
- 停服务 → 快照数据 → `mv` 原子替换 → 启动，停机约 0.28 秒。
- 公网入口 `/opt/nginx/conf.d/site.conf`（Docker nginx，多个产品共用）按路径白名单转发 RDesk。新增 `/session/close` 与 `/session/screen/stop` 两条精确匹配（80 与 443 两个 server 段，与 `/session/trust` 写法一致），`nginx -t` 通过后重载。备份 `site.conf.bak-rdesk-session-close-20260928`。其他站点抽查正常；`conflicting server name` 警告在此之前就存在。

## 上线后验证

- 本地与公网 `/health` 正常；重启后真实在线的被控端自动重新注册（`preview_count` 回到 1）；部署后日志没有 WARN/ERROR。
- `python3 scripts/check_wake_pairing.py --base https://qisw.top` 通过，临时账号已删除。
- `python3 scripts/check_capture_on_demand.py --base https://qisw.top` 17 步全部通过：无人观看时上传 409 → 密码观看者取帧产生租约 → 按代次上传 200 并取回画面 → 经公网 `/session/close` 关闭后需求清零、旧代次上传 409 → 旧式主机无需观看者仍可上传。临时主机已注销。
- 没有审核凭据，也没有连接 adb，因此没有运行 `scripts/check_review_host.sh`。演示机属于旧式安卓上传路径，该路径已由冒烟覆盖，但这不等于演示机本身检查通过。

## 回滚

```sh
systemctl stop rdesk-server
cp -p /usr/local/bin/rdesk-server.bak-20260928 /usr/local/bin/rdesk-server
# 如需恢复数据，用 /var/backups/rdesk-server/20260928-predeploy-dbdc2e2/data
systemctl start rdesk-server
```

旧服务端不认识按需协议。新版 Mac 客户端在旧服务端上会保持待命、提示中继需要更新，不会退回持续截屏。nginx 新增的两条规则在旧服务端上无害，可以保留。

## 未覆盖

- 没有用真实 Mac 经公网中继观看；上述冒烟只验证服务端协议，不代表真实采集和显示。
- 官网 Mac 安装包仍为 2.2.3，不含按需采集。本机已安装 2.2.5（22）。
