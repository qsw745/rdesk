# RDesk 服务端部署

当前仓库里的 `rdesk-server` 是单进程 HTTP 服务。

## 生产机的构建边界

`101.37.21.147` 同时承载多个服务，仅有 2 GiB 内存。不要在该生产机直接运行 Cargo、Docker 镜像或前端构建。2026-09-20 的服务器端构建与持续读盘饱和、SSH 超时同时发生；单独限制 `CARGO_BUILD_JOBS=1` 并不足以保护生产服务。

应先在本地构建环境生成 Linux x86_64 制品（必要时使用本地交叉编译、容器或虚拟机），验证其 GLIBC / 动态库要求与生产系统兼容，然后上传成品、保留旧二进制、原子替换并执行健康检查。部署构建分离前，不在生产机重试构建。详情见 [故障调查记录](../docs/validation/server-io-incident-2026-09-20.md)。

- 实际监听端口: `21116/tcp`
- `21117` 目前只保留为后续 relay 参数，当前 MVP 没有单独监听
- 客户端需要把“信令服务器”配置成 `http://<服务器IP>:21116`，或者反代后的域名

## 方案一：直接暴露 21116 端口

适合安全组已经放通 `21116/tcp` 的环境，不依赖 nginx。

```bash
sudo useradd --system --home /var/lib/rdesk-server --shell /usr/sbin/nologin rdesk
sudo mkdir -p /var/lib/rdesk-server/data
sudo chown -R rdesk:rdesk /var/lib/rdesk-server

sudo install -m 0755 ./target/release/rdesk-server /usr/local/bin/rdesk-server
sudo install -m 0644 ./deploy/rdesk-server.service /etc/systemd/system/rdesk-server.service

sudo systemctl daemon-reload
sudo systemctl enable --now rdesk-server
sudo systemctl status rdesk-server
```

放通安全组或防火墙:

- `21116/tcp`

客户端填写:

- `http://101.37.21.147:21116`

## 方案二：走 nginx 反代

适合继续保留现有 `80/443` 入口，或者云安全组只放通了 `80/tcp` 的环境。

要求:

- 准备一个单独域名，例如 `qisw.top`
- DNS 指向 `101.37.21.147`

部署步骤:

```bash
sudo cp deploy/nginx.rdesk-server.conf /etc/nginx/conf.d/rdesk.conf
sudo nginx -t
sudo systemctl reload nginx
```

公网 HTTP 入口可直接填写:

- `http://qisw.top`

完成证书签发并更新 DNS 后，客户端也可以填写:

- `https://qisw.top`

说明:

- 反代配置里已经带了 `X-Forwarded-Host` 和 `X-Forwarded-Proto`
- 服务端现在会按反代头返回正确的预览地址，不会再把 HTTPS 入口错误地回写成 HTTP

## 常用排查

```bash
curl -i http://127.0.0.1:21116/health
sudo journalctl -u rdesk-server -n 100 --no-pager
ss -lntp | grep 21116
```
