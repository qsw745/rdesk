# 应用内更新

用户已要求实现此前缺少的自动更新提醒、手动检查及下载安装。本次新增更新子系统，直接按已授权范围执行；不重复请求授权。沿用自有官网及所有平台本地构建规则。

## 行为

- 应用启动、回到前台时自动检查，成功后六小时内不重复请求，失败后至少一小时再自动尝试。可以关闭自动检查；手动检查不受节流或忽略版本限制。
- 主界面显示可关闭的新版本提示，不弹窗抢占远控；关于页提供检查、版本、说明、下载进度、取消、失败重试、安装。用户明确点击才下载/打开安装程序，不静默替换运行文件。
- Windows 下载 EXE 并打开系统安装向导；安卓下载 APK、验证同包名/同签名/更高版本，并用受限 FileProvider 打开系统安装；安装来源授权单独由用户操作。Mac 按当前进程架构选择 DMG/ZIP，下载后打开并说明拖入应用程序。iPhone 仅打开官方 App Store，不下载/执行 IPA。
- 当前商店版与测试版分开比较；已安装较新测试版不提示降级，也不把未发布版本作为更新。先安装含更新能力的新版，旧 2.2.0 不会凭网站更新获得新功能。
- 本轮自动提醒发生在应用运行期间；不增加 APNs/厂商推送或应用关闭时的通知服务。

## 数据与安全

固定读取 `https://qisw.top/rdesk/releases.json`，不跟随账号服务器配置，不携带账号凭据。兼容已有清单，加入可选 build_number 和 release_notes。数字三段版本比较，禁止降级；同版仅在明确存在更高 build_number 时提示。

仅允许官网 /rdesk/dl/ 下与平台、版本相匹配的固定文件名；iOS 仅允许既有 App Store 应用 ID。拒绝重定向、非 HTTPS、未知平台、畸形版本、非法大小/摘要、空或 HTML 响应。元数据最多 128 KiB，安装包最多 512 MiB。下载流式写入专用临时目录，显示进度；核对长度和 SHA-256 后才重命名可用文件，交给安装器之前再校验一次。取消、超时、损坏文件不得启动安装器；不自动重启/关机。

## 分层

- UpdateRelease / AppVersion：清单、版本、平台和下载地址校验。
- AppUpdateService：有界 HTTP、文件下载/校验/取消与平台安装桥接。
- AppUpdateProvider：节流、忽略版本、状态及安装交接，不谎报安装成功。
- UpdateCard / UpdateBanner / UpdateLifecycle：关于页、主界面提示及前后台检查。
- Android AppUpdatePlugin：最小安装权限和受限 APK 分享；其他平台复用系统打开能力。

## 验收与发布

回归覆盖数字版本/同版 build、测试版与商店、架构选择、来源限制、错误/超限/截断下载、校验失败、取消、单一下载、节流、忽略和手动检查、销毁迟到结果、正在远控时安装限制。全量 Flutter 测试、静态检查及本地四平台构建；本地 Windows VM 验证安装与进程启动，安卓真实安装能力视连接设备单独记录。iPhone 本地安装，不上传 App Store。保留现有脏工作与 Mac 安装，发行不混入未提交捕获改动。官网预构建上传、保留旧 URL、公开摘要核验后推送 master。

依赖与平台依据：[url_launcher 6.3.2](https://pub.dev/packages/url_launcher/versions/6.3.2)、[Android FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)、[安装来源检查](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls())。
