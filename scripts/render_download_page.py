#!/usr/bin/env python3
"""Render the public download pages from verified release metadata."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'deploy/releases.json').read_text())

def esc(value):
    return html.escape(str(value), quote=True)

cards = []
for item in data['platforms']:
    alternate = ''
    if item.get('alternate'):
        alternate = f'<a class="secondary" href="{esc(item["alternate"]["url"])}">{esc(item["alternate"]["label"])}</a>'
    integrity = ''
    if item.get('sha256'):
        integrity = f'<details><summary>文件校验 SHA-256</summary><code>{esc(item["sha256"])}</code></details>'
    cards.append(f'''<article class="platform" id="{esc(item['id'])}">
      <div class="platform-top"><span class="platform-icon" aria-hidden="true">{esc(item['symbol'])}</span><span class="tag">{esc(item['tag'])}</span></div>
      <h3>{esc(item['name'])}</h3><p class="version">{esc(item['version'])} · {esc(item['size'])}</p>
      <p class="requirements">{esc(item['requirements'])}</p><p class="capability">{esc(item['capability'])}</p>
      <a class="button" href="{esc(item['url'])}">{esc(item['button'])}<span aria-hidden="true"> ↗</span></a>
      {alternate}<p class="install-note">{esc(item['note'])}</p>{integrity}</article>''')
status = ('远程开机配套服务已部署。实际唤醒仍需电脑硬件支持，并完成家中助手配置；隔夜稳定性请按说明实测。'
          if data['wake_service_ready'] else '远程开机客户端已提供，配套服务尚待部署。目前可先安装并使用已支持的远程连接功能。')
page = '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RDesk 官网 · 电脑与手机远程连接</title>
<meta name="description" content="RDesk 官方下载。获取 macOS、Windows、Android 安装包，或前往 App Store 安装 iPhone 与 iPad 版。查看远程开机配置与平台能力。">
<link rel="canonical" href="https://qsw745.github.io/rdesk/"><link rel="icon" href="/rdesk/icon.png">
<meta name="theme-color" content="#f5f7fb">
<style>
:root{color-scheme:light dark;--bg:#f5f7fb;--surface:#fff;--ink:#152238;--muted:#596579;--line:#dfe5ee;--blue:#175bea;--soft:#eaf0ff}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}a{color:var(--blue);text-decoration:none}a:hover{text-decoration:underline}a:focus-visible,summary:focus-visible{outline:3px solid #ffb342;outline-offset:5px}header{border-bottom:1px solid var(--line);background:var(--surface)}nav{max-width:1180px;margin:auto;padding:18px 28px;display:flex;align-items:center;gap:24px}nav .brand{display:flex;align-items:center;gap:10px;color:var(--ink);font-weight:750;font-size:21px;margin-right:auto}nav img{width:34px;height:34px;border-radius:9px}nav>a:not(.brand){font-size:14px;color:var(--muted)}main{max-width:1180px;margin:auto;padding:0 28px}.hero{padding:74px 0 44px;max-width:800px}.eyebrow{color:var(--blue);font-size:13px;letter-spacing:.14em;font-weight:700}.hero h1{font-size:clamp(34px,5.5vw,62px);line-height:1.18;letter-spacing:-.045em;margin:18px 0 24px}.hero p{font-size:18px;color:var(--muted);max-width:650px;margin:0}.hero .facts{display:flex;flex-wrap:wrap;gap:12px;margin-top:25px}.facts span{border:1px solid var(--line);border-radius:50px;padding:4px 12px;font-size:13px;color:var(--muted)}.section-head{display:flex;justify-content:space-between;align-items:baseline;gap:18px;margin:20px 0}h2{font-size:24px;letter-spacing:-.02em;margin:0}.section-head p{font-size:13px;color:var(--muted);margin:0}.platforms{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}.platform{min-width:0;background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:24px;display:flex;flex-direction:column}.platform-top{display:flex;align-items:center;justify-content:space-between;gap:8px}.platform-icon{display:grid;place-items:center;width:44px;height:44px;background:var(--soft);border-radius:12px;font-size:23px;font-weight:700;color:var(--blue)}.tag{font-size:11px;color:var(--muted)}h3{font-size:22px;margin:22px 0 5px}.version{font-size:13px;color:var(--muted);margin:0 0 18px}.requirements{font-size:14px;font-weight:600;min-height:46px;margin:0 0 10px}.capability{font-size:14px;color:var(--muted);margin:0 0 22px;flex:1}.button{display:flex;justify-content:space-between;align-items:center;border-radius:9px;padding:11px 13px;background:var(--blue);color:#fff;font-size:14px;font-weight:650}.button:hover{filter:brightness(1.08);text-decoration:none}.secondary{font-size:13px;margin-top:12px}.install-note{font-size:12px;line-height:1.7;color:var(--muted);margin:15px 0 0}details{font-size:12px;color:var(--muted);margin-top:15px}summary{cursor:pointer}code{display:block;overflow-wrap:anywhere;font-size:11px;margin-top:8px}.wake{margin:42px 0;padding:32px;border:1px solid var(--line);border-radius:18px;background:var(--surface)}.wake>p{max-width:830px;color:var(--muted)}.steps{display:grid;grid-template-columns:repeat(3,1fr);gap:24px;margin:28px 0}.steps strong{display:block;font-size:16px}.steps span{font-size:14px;color:var(--muted)}.number{color:var(--blue);font-size:12px;font-weight:800;margin-bottom:8px}.status{background:var(--soft);border-radius:9px;padding:14px 16px;font-size:14px}.faq{max-width:850px;margin:48px 0}.faq details{font-size:15px;padding:18px 0;border-bottom:1px solid var(--line);margin:0}.faq summary{font-weight:600;color:var(--ink)}.faq p{margin-bottom:0;color:var(--muted)}footer{border-top:1px solid var(--line);max-width:1124px;margin:40px auto 0;padding:24px 0 40px;display:flex;flex-wrap:wrap;gap:20px;font-size:13px;color:var(--muted)}footer span{margin-right:auto}
@media(max-width:1000px){.platforms{grid-template-columns:repeat(2,minmax(0,1fr))}.requirements{min-height:0}}@media(max-width:580px){nav{padding:14px 20px;gap:16px}nav .brand{font-size:19px}nav>a:not(.brand){font-size:12px}main{padding:0 20px}.hero{padding-top:46px}.hero p{font-size:16px}.platforms,.steps{grid-template-columns:1fr}.platform{padding:22px}.section-head{display:block}.section-head p{margin-top:6px}.wake{padding:24px}.requirements,.capability{min-height:0}.steps{gap:20px}footer{margin-left:20px;margin-right:20px}}
@media(prefers-color-scheme:dark){:root{--bg:#101621;--surface:#192230;--ink:#edf2fc;--muted:#abb7c9;--line:#303e52;--blue:#4e8cff;--soft:#203252}.button{background:#2767dd}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
</style></head><body>
<header><nav aria-label="主导航"><a class="brand" href="/rdesk/"><img src="/rdesk/icon.png" alt="">RDesk</a><a href="#download">下载</a><a href="#wake">远程开机</a><a href="/rdesk/support">支持</a></nav></header>
<main><section class="hero"><div class="eyebrow">RDESK · 官方网站</div><h1>电脑与手机，<br>连接到一起。</h1><p>从手边的设备访问另一台设备。选择适合你的版本，开始远程连接，或配置家中电脑的远程开机。</p><div class="facts"><span>核心功能免费</span><span>四个平台入口</span><span>官方文件下载</span></div></section>
<section id="download" aria-labelledby="download-heading"><div class="section-head"><h2 id="download-heading">选择你的设备</h2><p>更新于 __DATE__ · 各平台功能以说明为准</p></div><div class="platforms">__CARDS__</div></section>
<section class="wake" id="wake"><div class="eyebrow">新功能 · 远程开机预览</div><h2>出门之后，也能请求电脑开机。</h2><p>让家中长期供电的安卓手机接收开机请求，再通过家庭局域网唤醒插网线的 Windows 电脑。无需在路由器开放公网端口。</p><div class="steps"><div><div class="number">01 / 家中安卓手机</div><strong>启用开机助手</strong><span>登录同一账号，连接家庭 Wi-Fi，保持充电并允许后台运行。</span></div><div><div class="number">02 / Windows 电脑</div><strong>选择有线网卡</strong><span>确认主板与网卡支持网络唤醒，在 RDesk 中绑定家中助手。</span></div><div><div class="number">03 / 外出的设备</div><strong>发起请求，查看记录</strong><span>在「设置 → 远程开机」查看助手、发送回执和电脑应用上线状态。</span></div></div><p class="status">__STATUS__</p><p>“信号已发送”不代表电脑已启动；只有收到电脑应用心跳才显示上线。当前 App Store 版本尚不包含此项新功能。</p></section>
<section class="faq"><h2>下载前，你可能想了解</h2><details><summary>哪些设备可以被远程操作？</summary><p>Android 与 macOS 可作为被控端。Windows 当前提供控制端与远程开机配置，尚不支持共享 Windows 桌面给别人操作。iPhone/iPad 可作控制端，也可分享屏幕，但不能接收远程触控。</p></details><details><summary>iPhone 可以像安卓一样下载文件安装吗？</summary><p>官网的苹果手机按钮会前往 App Store。普通 IPA 文件不能像 APK 一样在任意 iPhone 上直接安装。</p></details><details><summary>安装后需要开启哪些权限？</summary><p>Mac 被控需要屏幕录制与辅助功能权限；Android 屏幕共享和远程操作按应用提示授权。独立的安卓开机助手仅需网络、通知与后台运行，不要求录屏或无障碍。</p></details><details><summary>远程开机为什么需要实测？</summary><p>不同主板、网卡、Windows 电源状态及安卓后台策略存在差异。先测试睡眠与刚关机，再测试蜂窝网络、隔夜、24 小时和 48 小时。失败时先看助手是否在线，再看发送回执与电脑应用心跳。</p></details><details><summary>旧系统还能下载旧版吗？</summary><p><a href="https://qisw.top/rdesk/dl/RDesk-2.1.0.dmg">macOS 2.1.0 旧版</a>保留供兼容性需要。旧版不包含新的远程开机功能。</p></details></section></main>
<footer><span>© 2026 RDesk · QSW</span><a href="__CHECKSUMS__">全部文件校验值</a><a href="/rdesk/support">技术支持</a><a href="/rdesk/privacy">隐私政策</a><a href="mailto:641742030@qq.com">联系我们</a></footer></body></html>'''
page = page.replace('__DATE__', esc(data['date'])).replace('__CARDS__', ''.join(cards)).replace('__STATUS__', status).replace('__CHECKSUMS__', esc(data['checksums_url']))
for name in ['index.html', 'download.html']:
    (ROOT / 'deploy' / name).write_text(page)
print('官网和下载页已生成。')
