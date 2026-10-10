# Windows 2.3.11 发布记录（2026-10-10）

## 起因

两个现场问题：

1. 用 Windows 控制一台有两块屏幕的 Mac，顶部只有一个「主显示器」。
2. 用 Windows 控制 Mac，点进输入框后打字，文字始终进不去。

## 原因

### 只显示一块屏

- 经公网中继时，观看端取屏幕列表的请求是 `GET /displays`。公网入口 nginx 按路径白名单转发，这条路径不在名单里，返回 404。观看端把「取不到」当成「只有一块屏」，整场只显示「主显示器」。被控端本身能列出并切换多块屏，局域网直连不受影响。
- `POST /settings/quality` 同样不在白名单里，经中继调画质一直没有到达被控端。
- 对照服务端全部路由后，白名单里缺的就是这两条。

### Mac 上打不了字

- Mac 被控端用 `osascript` 调 `System Events` 的 `keystroke` 来打字。应用以 Hardened Runtime 签名，没有 `com.apple.security.automation.apple-events` 授权，系统直接拒绝。系统日志里有对应记录：`policy for hardened runtime; service: kTCCServiceAppleEvents requires entitlement com.apple.security.automation.apple-events but it is missing for accessing={... com.qsw.rdesk ...}`，当天三个进程各一条。
- 所以文字到了 Mac，但从来没有被打进去，与焦点无关。公开的 Mac 2.3.5 签名方式相同，应当有同样的问题，没有单独验证。

### 顺带发现

- Mac 被控端的鼠标坐标一律按主屏换算。切到第二块屏后画面是对的，点击会落在主屏的对应位置。这台 Mac 的内建屏在主屏左侧，原点 x 为 -1728。
- 顶部标签上有一个关闭图标，点了没有任何反应。
- 浅色主题下，延迟未知时信号图标是白色，看不见。

## 改动

源码：提交 `ff56e2e`（版本 2.3.11+34）。

- 观看端：
  - 每块屏幕一个标签：「显示屏 N」加型号（没有型号时用分辨率），选中的浮起；悬停提示里有是否主显示器、型号、分辨率。
  - 切换时标签上显示进度；被控端没有切换成功时提示，并回到原来那块。一次只进行一个切换。
  - 取列表失败与「只有一块屏」分开：失败最多重试 3 次（2、4、6 秒后）。
  - 被控端报告了当前显示的是哪块屏时，标签跟着它。被控端的选择会保留到下一位观看者，此前新观看者的标签停在第一块，画面却可能是第二块。
  - 去掉无效的关闭图标；修正浅色主题下的信号图标颜色。
- Mac 被控端：
  - 文字输入改为应用自身发送 Unicode 键盘事件，走已授权的辅助功能权限，不再调用 AppleScript。
  - 点击、右键、拖动、滚动改为应用自身发送，不再经 Python 子进程；坐标按正在采集的那块屏换算。
  - 屏幕列表带上型号（如 VG27AQL3A、Built-in Retina Display）和当前选中项。
  - 这部分原生实现来自另一个工作区（`xenodochial-sanderson-0ccba5`）里未提交的改动，本次合入主线并保留 Windows 分支。那个工作区的改动现在是重复的。
- Windows 被控端：屏幕列表带上当前选中项。

## 入口配置：已修改，未生效

`101.37.21.147` 上的 `/opt/nginx/conf.d/site.conf` 已在 80 与 443 两段各加入 `location = /displays` 和 `location = /settings/quality`，写法与相邻的 `/clipboard/` 一致。原文件备份为同目录的 `site.conf.bak-20261010-displays`，`docker exec nginx nginx -t` 通过。

**重载没有执行**：执行 `nginx -s reload` 的命令被权限检查拦下，没有绕过。在重载之前：

- 经中继连接仍然只显示一块屏，2.3.11 也一样；经中继调画质仍然不生效。
- 局域网直连不受影响。
- 如果这个 nginx 因为别的原因重启，新配置会一并生效。

重载并核对的命令：

```sh
ssh root@101.37.21.147 'docker exec nginx nginx -t && docker exec nginx nginx -s reload'
curl -s -o /dev/null -w '%{http_code}\n' 'https://qisw.top/displays?device_id=a&token=b'   # 应为 401，不是 404
```

回滚：把备份文件复制回 `site.conf` 后重载。

## 构建与验证

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| RDesk-2.3.11-windows-x64-setup.exe | 13327087 | `7ef7143a404cc9a2e8d5dc0f959f614d76a7b082e45eef699b49a73dc7ff2d0f` |
| RDesk-2.3.11-windows-x64-portable.zip | 14453844 | `48b1bd389a97a3bf12cd8efc84d575ef2ae29fb1d5f4327b316e27ba81c96466` |

- 本地 Parallels Windows 11，`git archive` 导出 `ff56e2e` 到 `C:\dev\rdesk-2.3.11` 后运行 `scripts\build_windows.ps1`：无编译警告，x64、启动与静默安装检查通过；取回本机后摘要一致。
- `flutter analyze` 无问题，完整 `flutter test` 349 项通过。新增：屏幕列表解析、取列表重试与停止、切换确认与回退、并发切换、跟随被控端选中项、标签的点击与无障碍点击、文字放大时不被裁切、顶栏在窄窗口下不溢出。
- Mac 原生输入映射的独立检查 26 项通过（`scripts/tests/macos_input_mapping_test.swift`，不向系统发送任何事件）：归一化坐标到各种屏幕排布的换算、拖动路径、文字拆分。
- 发布构建在虚拟机里开启被控后，经局域网接口取屏幕列表：返回 1 块屏并带 `selected: true`；`switch_monitor_0` 返回成功。
- 标签样式用真实字体渲染成图后目视检查：1、2、3 块屏，明暗两个主题。
- Mac：本机 `build_install.sh macos` 构建、签名、安装 2.3.11（34），签名校验通过，二进制里有新的原生输入入口。未公证、未发布。

## 官网

- 本地打包（成品 SHA-256 `8745ee23…85064494`），上传 `rdesk-new` 摘要一致，解压到 `releases/20261010-2.3.11`，`MANIFEST.sha256` 通过，带上上一版 2.3.10 的两个安装包，原子切换 `current`。
- 公网：四个页面 200；`releases.json` 与本地逐字节一致；两个新文件 Content-Length、Range 206、完整下载 SHA-256 一致。
- 按「只留当前版和上一版」删除了 `releases/20261010-2.3.9`；`releases/20261010-2.3.10` 是回滚目标，清单校验通过。

## 未覆盖

- **没有在真实的两块屏上验证过**：标签、切换、切换后点击落点都没有用真实连接操作过。屏幕型号只用独立脚本在这台 Mac 上读过，结果是 VG27AQL3A（主屏）和 Built-in Retina Display。
- **Mac 原生文字和鼠标输入没有实际注入过**：测试只覆盖换算和拆分，没有向这台正在使用的 Mac 发送任何点击或按键。应用是否已获得辅助功能权限也没有读到；没有权限时这些操作会返回失败。
- **Windows 观看端开着中文输入法时能否打字，没有验证。** 键盘转发直接读按键，没有接入输入法；输入法处于中文状态时，按键可能被输入法截走而发不出去。如果切到英文状态能打字、中文状态不能，就是这个原因，需要另做输入法接入。
- 经中继的多屏和画质设置依赖上面那次重载。
- 屏幕列表只在连上时取一次：会话中途插拔显示器，标签不会更新。
- Windows 被控端不报告显示器型号，标签上显示分辨率。
- Mac 2.3.5 公开版没有这些被控端修正。
