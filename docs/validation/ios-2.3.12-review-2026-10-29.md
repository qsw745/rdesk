# iOS 2.3.12（35）送审记录（2026-10-29）

## 授权与范围

用户明确恢复 iOS 送审，按真实审核访问方案进行，不以专用持续在线演示机或 USB 连接作为前提。沿用已有测试账号及审核联系信息，不承诺旧示例主机在线。沿用审核通过后自动发布设置。

## 本地构建与验证

- 源码基线 `f7103f7`；应用功能代码与已发布三端 2.3.12 相同，核心安全修复提交 `e165576`。
- 本地 `flutter build ipa --release --no-pub --export-options-plist=ios/ExportOptions.plist` 成功；无服务器或云 CI 构建。
- 成品：`flutter_client/build/ios/ipa/随控.ipa`，20,770,208 字节，SHA-256 `ade824b4ffa676b1168687772dff4f5cb1b21d635cba3c4152a890e9f7794f18`。
- 从最终 IPA 解包核验：主 App `com.qsw.rdesk` 与屏幕共享扩展 `com.qsw.rdesk.BroadcastExtension` 均为 2.3.12（35）、最低 iOS 15；均包含应用自有隐私清单，Apple Distribution 签名及无调试权限的 App Store profile 校验通过。未声明相机或相册权限，未加入非豁免加密声明。
- App Review 真实性、官方服务策略、账号恢复切片共 23 项通过。此前同版本完整 Flutter 回归 367 项通过、1 项按平台跳过。
- Flutter 提示默认启动图占位警告，未作额外界面变更；正式签名与构建成功已分别核验。该警告不能当作上传失败或审核通过的证据。

## 审核材料

- 新版本资源 ID：`462bc7c3-95f4-4b25-99e5-e7116720b93e`，创建后状态 `PREPARE_FOR_SUBMISSION`，发布方式 `AFTER_APPROVAL`。
- 继承 `zh-Hans` 公开描述、支持 URL、关键词，以及 5 张 iPhone 6.5 英寸和 3 张 iPad 12.9 英寸截图，所有截图交付状态均为 `COMPLETE`。
- 更新说明写入网络安全、来源隔离及远程操作改进；公开描述、更新说明、关键词、推广文本均检查不含 Android/安卓/Windows。
- 新审核备注 1244 字符，已写入并逐字读回；描述实际测试账号、审核方可自行配置 Mac 的连接步骤、无持续在线演示主机、免费模式、iOS 屏幕共享限制、官方 HTTPS/WSS 与局域网 HTTP 的边界、账号删除入口。
- 原审核联系信息和测试账号字段完整继承；通过官方服务登录接口验证该测试账号可成功登录。没有把账号、密码、旧示例主机凭据或认证令牌写入仓库/输出。
- 隐私页、全球支持页、服务健康接口的 GET/HEAD 均为 200，使用 Safari/iPad User-Agent；未改动这些公开页面。

## 上传与提交

2026-10-29 18:14:49 CST，`altool` 返回 `UPLOAD SUCCEEDED with no errors`，Delivery UUID `29ae71a8-98ea-46da-aea0-60326bfd1f7c`，接收 20,770,208 字节。上传成功已确认。

- 构建资源 ID：`29ae71a8-98ea-46da-aea0-60326bfd1f7c`，所属预发布版本 2.3.12；处理完成为 `VALID`。此前从新版本关联构建读回 `PROCESSING`，处理完成后再继续，没有重复上传。
- 按项目现有标准 TLS/WSS 加密豁免依据，将 `usesNonExemptEncryption` 设为 `false` 并直接读回确认；`scripts/asc.py builds` 也显示构建 35 为 VALID、豁免、未过期。没有新增自实现加密或更改本次合规依据。
- 版本 2.3.12 已选入构建 35，并再次从版本的 build 关联读回匹配。
- 提交时间：**2026-10-29 18:21:54 CST**；审核提交 ID：`7921d86d-7529-4a4a-8ca7-1ac9c15fa16a`。
- 创建审核提交、加入版本提交项、PATCH `submitted: true` 均成功。独立 GET 读回：审核提交 `WAITING_FOR_REVIEW`，App 版本 `WAITING_FOR_REVIEW`，发布方式 `AFTER_APPROVAL`；提交中仅有一个匹配本版本的项目（项目状态 `READY_FOR_REVIEW`）。
- `altool --build-status` 返回 VALID、APP_STORE_ELIGIBLE；TestFlight 内部群组的实际读回仍未包含构建 35，本轮没有主动把它加入群组。这不影响上述 App Store 提交，不宣称已向 TestFlight 测试员分发。
- **当前结论：已提交、等待审核；未批准、未公开上架。** 商店当前已上架版本仍为 2.3.2，官网 iOS 版本清单保持 2.3.2。
