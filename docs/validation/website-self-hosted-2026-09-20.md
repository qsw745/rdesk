# 官网迁移到自有服务器（2026-09-20）

## 运行位置

- 正式地址：`https://qisw.top/rdesk/`；`https://qisw.top/` 保留 SiteHarbor，新增 RDesk 产品入口；`/go/rdesk` 跳转到官网。
- 新静态源站：`124.223.200.182`，SSH `rdesk-new` / `ubuntu`，sudo 管理 nginx。网站成品目录 `/opt/rdesk-website/releases/20260920-2.1.2/rdesk`，`/opt/rdesk-website/current` 为相对软链接。
- 新源站 nginx：在已有受限的 `wenheng-origin.internal` HTTPS server 中 include `/etc/nginx/snippets/rdesk-website.conf`。沿用其他产品的证书与入口 IP 白名单，入口校验证书，不新增公网明文文件服务。
- 域名仍由 `101.37.21.147` 的 Docker nginx 接入；`/opt/nginx/conf.d/site.conf` 的 HTTPS server include `/opt/nginx/conf.d/rdesk-website.inc`，把 `/rdesk/` 加密转发到新服务器。HTTP 同路径转 HTTPS。
- 未修改 DNS、域名首页归属、RDesk 账号/中继/远程开机服务或其他产品上游。
- 官网当前 Mac 2.1.1、Windows/Android 2.1.2 安装文件和校验清单均使用 `https://qisw.top/rdesk/dl/`；iOS 保留 App Store 入口。2.1.0 历史下载路径仍由入口旧文件提供，避免已安装客户端的旧链接失效。

## 构建与部署

页面由本地 `scripts/prepare_website.py` 生成。所有安装文件沿用之前本地构建并验证的成品，迁移前逐一核对大小与 SHA-256。上传后在源站按 `MANIFEST.sha256` 再次核对。服务器只解压、校验、切换与重载，不运行任何编译或依赖安装。

新增 `scripts/package_website.py` 可复用本地打包及完整性验证；它只接受匹配元数据摘要的安装文件。配置片段位于 `deploy/nginx.rdesk-website-{origin,edge}.conf`。本次部署不依赖 GitHub Pages 或 Actions，旧 Pages workflow 已移除，GitHub Pages 站点停用 API 返回 204。源代码仓库与历史 Release 保留；独立的 App Store `rdesk-support` 支持站不在本次迁移范围。

## 备份与回滚

- 新源站首次配置备份：`/opt/rdesk-website/backups/20260920-initial/wenheng-origin.conf`。
- 域名入口备份：`/var/backups/rdesk-ops/20260920-website-migration/site.conf`。历史 `/data/website/rdesk` 及其旧安装文件未覆盖。
- 如需撤销 nginx 迁移，先恢复域名入口配置，`docker exec nginx nginx -t` 后平滑重载；再恢复源站的原配置并 `nginx -t && systemctl reload nginx`。新增 snippet 没有独立顶层加载，不修改其他产品配置。
- 后续页面更新保留旧 release 目录，回滚时原子切换 `current` 链接即可。
- SiteHarbor 本次新增条目 ID：`cmu9lhluy0001pd3nqffuuws5`，slug `rdesk`；未修改其他条目、分类或点击数。入口回滚时可将该条目停用，避免回到旧站后产生误导。
- 源站使用现有证书，有效期及续期方式沿用问衡运维说明（当前记录到 2027-09-08，续期时同步入口信任证书）。不要仅移除私有源站校验来处理证书问题。

## 已验证

- 两端 nginx 配置检查通过并平滑重载；入口已有重复 IP server_name 警告，本次未引入或调整该历史项。
- 公网页面与本地成品逐字节一致，浏览器显示自有域名的全部安装包地址，未残留 GitHub 下载链接。
- 官网、下载、支持、隐私页面均返回 200；`/rdesk` 自动规范到 `/rdesk/`。域名首页显示 RDesk，`/go/rdesk` 跳转正确。
- RDesk `/health` 200，未登录 `/api/wake/targets` 401；问衡、Clario、ProfileDock、Birthday 路径均可访问，旧 2.1.0 两个下载地址仍为 200。
- 五个当前安装文件均从 `qisw.top/rdesk/dl/` 完整下载，长度和 SHA-256 全部与 `deploy/releases.json` 相符；每个文件 HEAD 均有正确长度及 attachment，Range 请求均为 206。
- GitHub Pages 停用后 GET Pages API 返回 404，仓库没有剩余 `.github/workflows/*.yml`，后续推送不触发官网或应用云端构建。
