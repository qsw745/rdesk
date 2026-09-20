# 远程开机接口部署与公网路由修复

时间：2026-09-20 15:58–16:00，北京时间。

## 用户故障与原因

Windows 2.1.1 已安装，远程开机页显示“服务器暂不支持远程开机”。确认有两处阻塞：

1. 线上旧 RDesk 程序没有 `/api/wake/targets` 路由，本机请求也返回 404。
2. 多业务 nginx 的 HTTPS 配置未转发 `/api/wake/`，请求落入其他业务的 `/api/` 路由。更新程序后，本机已返回 401，公网仍返回 404，进一步定位到此处。

此结果不能用来判断用户 Windows 网卡、BIOS 或安卓后台是否设置正确；该阶段的请求还没有进入唤醒链路。

## 本地构建与验证

- 源码：提交 `77f2caf` 的干净 Git 快照，未混入工作区原有 macOS 采集与其他改动；复制本地依赖锁文件用于固定依赖。
- 在本机 macOS 使用 `cargo zigbuild -p rdesk_server --release --locked --target x86_64-unknown-linux-musl` 交叉编译。
- 成品为 Linux x86_64 静态链接 ELF，避免目标 Anolis 8 的 GLIBC 2.28 兼容问题；在本机 Linux amd64 容器运行实际成品完成协议验收。
- `cargo test -p rdesk_server`：14 项通过。
- 本地原生程序及本机 Linux 容器中的交叉编译成品均通过 `scripts/check_wake_protocol.py`，覆盖账号隔离、角色拒绝、领取、发送授权、回执、上线、去重与凭据撤销。
- 成品 SHA-256：`cfb2a190dea144fe8ff6cb2aaf76189fdc4d29dbc20122928026b80406a49c8c`；上传到服务器后再次校验一致。
- 没有在服务器或 GitHub Actions 编译。服务器仅接收成品、备份、切换和健康检查。

## 部署与回滚资料

- 服务：`rdesk-server`；运行程序：`/usr/local/bin/rdesk-server`。
- 先停止服务，再备份用户和会话数据，然后替换程序并启动；原业务账号数据保留。
- 备份目录：服务器 `/var/backups/rdesk-ops/20260920-wake-deploy/`，目录权限 0700，包含 `rdesk-server.previous`、`rdesk-server.service`、`data/` 和 `site.conf.previous`。
- nginx 修改：`/opt/nginx/conf.d/site.conf` 的 HTTPS server 增加 `location ^~ /api/wake/`，上游为 `http://172.30.215.161:21116`，保留 Host / Forwarded 头、关闭代理缓冲、读取超时 20 秒；HTTP 对应路径转到 HTTPS。
- `nginx -t` 通过后平滑 reload，未重启 nginx 容器。已有重复 IP server_name 警告仍在，不影响此次配置通过。
- 回滚前先停止 RDesk 并另外保留升级后的用户数据。恢复旧程序及匹配数据时必须恢复数据文件 `rdesk:rdesk` 属主；旧程序写入用户文件会丢弃新 wake 字段，因此不得只降级程序而忽略新配置。恢复旧 nginx 配置后须先 `nginx -t`，再 reload。不要覆盖升级后新增的正常用户操作。

## 公网验收与尚未覆盖的范围

通过实际 HTTPS 入口使用一个随机临时账号完成：注册 → 创建模拟助手和电脑 → 助手轮询 → 请求开机 → 领取 → 授权发送 → `sent` 回执 → 模拟电脑心跳 → `online`。

验收没有发送 UDP 魔术包，没有控制任何真实电脑。结束后删除本轮临时账号与配置，并验证令牌返回 401；没有保留测试凭据。该结果证明公网服务协议已接通，不证明物理关机唤醒、锁屏后台或隔夜稳定性。

原已安装客户端可刷新页面重新配置。UI 简化和新版安装包属于后续改版工作，不能把此次服务端部署描述成界面已经更新。
