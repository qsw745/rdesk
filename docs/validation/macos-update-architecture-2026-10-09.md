# macOS 更新下载故障修复（2026-10-09）

## 结果和范围

本机已备份旧版并安装随控 **2.3.5（28）**，默认入口为 `lib/main.dart`。实际 UI 显示新版本，原账号仍登录，屏幕录制和辅助功能仍显示已授权。全部 12 个 Mach-O 文件包含 arm64，Developer ID、Team、Hardened Runtime、嵌入开机助手及深度严格签名检查通过。

本记录对应前一阶段的本机修复：当时未替换官网成品，也未提交 App Store；当时官网清单为 macOS 2.3.2（25），该 Apple 芯片安装包也包含错误架构动态库，不能作为修复包。用户随后明确授权 Apple 公证与官网替换，后续发行进展见 [macOS 2.3.5 发布记录](release-2.3.5-macos-2026-10-09.md)。本地安装、下载传输验收、Apple 公证和官网发布分别记录。

## 根因证据

- 本机旧版为 2.3.1（24）：点击下载约 0.4 秒后显示“下载失败，请检查网络后重新下载”，没有产生新的下载缓存子目录。
- 官网清单 GET/HEAD 为 200；安装包 HEAD 为 200、Range 为 206，无重定向。完整下载 `RDesk-2.3.2-macos-arm64.dmg` 为 16,833,000 字节，SHA-256 为 `2b0d63bcdcba71cf8a2ddadf82eacde4d5aa44e2b93ce74f8653b516273d67c0`，均与清单相符。
- 旧安装版及只读挂载的官网 2.3.2 DMG：主程序与 Dart AOT 为 arm64，但 `objective_c.framework/objective_c` 只有 x86_64；NativeAssetsManifest 的 macos_arm64 条目却指向它。
- 相同 Developer ID / Hardened Runtime 的隔离 Release 探针，装入旧框架后，真实 `getTemporaryDirectory()` 抛出 `ArgumentError` / `DOBJC_initializeApi` 加载错误：缺少兼容架构，已有 x86_64，要求 arm64。换成正确框架后，真实缓存路径读取、完整官网包下载和再次 SHA-256 校验成功。
- `path_provider_foundation 2.6.0` 通过 Objective-C FFI 获取缓存路径。原有流式下载测试注入临时目录，未覆盖这条原生路径；原签名检查也未验证框架架构。

Flutter 按架构保存构建图，但原生库最终输出共享 `build/native_assets/macos`。切换架构后复用旧构建图，可能将共享目录内另一架构的库复制到应用。独立 Xcode DerivedData 不足以隔离该输出。

## 改动

- 本地安装及正式 macOS 打包入口在构建前清理 `.dart_tool/flutter_build` 和 `build/native_assets/macos`，同一目录的构建保持串行。
- 新增全包 Mach-O 架构门禁并接入安装／发行签名验收，覆盖框架、无扩展名原生库、嵌入助手及通用程序的全部 slice。
- 缓存获取、创建和打开失败改为明确的缓存错误提示，不再误报为网络问题；失败后仍可重试，下载来源／重定向／大小／摘要校验保持原要求。
- 保留无账号、无远控的原生更新诊断工具，便于后续签名 Release 验收。

## 验证

- 新增缓存回归测试先 RED：原生接口异常原样抛出，不能识别为缓存错误；修复后 GREEN。
- `flutter test test/app_update_test.dart test/app_update_ui_test.dart test/review_truthfulness_test.dart`：22 项通过，包含缓存失败不发请求、重试恢复及目录不可创建。
- 架构检查的真实 clang / lipo fixtures：9 项 RED → 9 项 GREEN，覆盖错误框架、错误助手、通用程序缺 slice、匹配架构、无执行位框架、符号链接去重及非 Mach-O 资源。
- `flutter analyze`、`bash -n`、`git diff --check` 通过。
- 本机正常主机权限下 `bash scripts/verify_macos_install.sh /Applications/rdesk.app` 完整通过。受限沙盒里的 codesign 曾报无效签名，正常主机权限复验通过，不据此重签或放宽运行时保护。
- 本机 UI 再次检查更新显示“当前安装版本高于公开版本（2.3.2），无需降级”。

这一阶段完成时，官网发行尚需重新生成并验证两种 Mac 成品、公证与装订，再更新清单和公开下载入口；这些后续步骤的结果以独立的发行记录为准。
