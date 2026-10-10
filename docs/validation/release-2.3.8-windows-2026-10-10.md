# Windows 2.3.8 发布记录（2026-10-10）

## 内容

- 源码：提交 `67833c3`（版本 2.3.8+31）。新增实体键盘转发与 Mac 到 Windows 的按键映射：
  - 观看端在远控画面获得焦点时转发实体键盘。普通字符按文字发送；功能键和带修饰键的组合键按按键发送，指令形如 `key:ctrl+shift+z`，沿用现有的动作通道，服务端未改动。按键逐个按序发送，等待期间连续输入的文字合并为一次，积压超过 64 个时丢弃新按键。
  - Mac 控制 Windows 时，「设置 → 远控 Windows 按键映射」可指定 Command、Option、Control、Delete、Fn+Delete 对应的 Windows 按键；默认 Command=Win、Option=Alt、Control=Ctrl、Delete=Backspace、Fn+Delete=Delete。该设置只在 Mac 上显示。⌘Q、⌘W、⌘H、⌘M 不转发，留给本机窗口。
  - Windows 被控端解析通用按键指令；格式不对、未知按键或未知修饰键一律拒绝。2.3.7 及更早的被控端不认识这类指令，会返回失败。
  - Mac、安卓被控端只会收到它们已实现的按键（文字、回车、删除，Mac 另有 Esc、Tab、方向键和全选、复制、粘贴、剪切、撤销、重做）。
- 只发布 Windows。macOS 2.3.5（28）、Android 2.3.2（25）、iOS 商店 2.1.0 不变；带映射设置的 Mac 控制端只装在开发机上（本地签名的 2.3.8，未公证、未发布）。

## 构建与验证

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| RDesk-2.3.8-windows-x64-setup.exe | 13214652 | `ce774e827e8f211cbaf16b1f86881d54cde049e1745cf061d00330e17a17445f` |
| RDesk-2.3.8-windows-x64-portable.zip | 14274087 | `b0545519c85655785b2278347a18e1d94994e65a9b9ee803dfd3d0b0b6ef047b` |

- 本地 Parallels Windows 11 + VS2022，`git archive` 导出 `67833c3` 到 `C:\dev\rdesk-2.3.8` 后运行 `scripts\build_windows.ps1`：无编译警告，x64、启动与静默安装检查通过。原生代码相对 2.3.7 没有变化。
- `flutter analyze` 无问题，完整 `flutter test` 270 项通过。新增测试覆盖按键翻译（各被控系统、映射改动、本机保留的快捷键）、指令解析、发送队列的顺序与合并、映射设置的保存与设置页、转发组件（仅观看、焦点在输入框时不发送）。
- 用发布构建本身、经应用的局域网接口，在应用自己的输入框里逐步核对画面：输入 123456789 后 Home、Shift+→ 三次、Delete 得到 456789；End、Backspace 得到 45678；Ctrl+A、Ctrl+C、End、Ctrl+V 得到 4567845678；Ctrl+Z 回到 45678；Ctrl+A、Backspace 清空。`key:hyper+a` 与 `key:ctrl+nosuchkey` 返回失败。结束后关闭被控，端口不再监听。

## 官网

- 本地打包（成品 SHA-256 `b244b0f6…cc5b3ded`），上传 `rdesk-new` 摘要一致，解压到 `/opt/rdesk-website/releases/20261010-2.3.8`，`MANIFEST.sha256` 通过，历次安装包与上一版目录比对无缺失，原子切换 `current`。`releases/20261010-2.3.7` 保留可回滚。
- 公网：四个页面 200；`releases.json` 与本地逐字节一致；两个新文件 Content-Length、Range 206、完整下载 SHA-256 一致；2.3.7、2.3.6、2.3.2 Windows、2.3.5 Mac、2.3.2 Android 链接仍为 200。

## 未覆盖

- 没有用真实键盘在 Mac 上按键验证：按键捕获和映射只经过组件测试，虚拟机里验证的是 Windows 被控端收到指令之后的部分。⌘C 这类同时也是 Mac 菜单快捷键的组合是否先到应用、Option 组合键的实际键值、输入法开启时的表现，都要在真机上确认。
- Windows 作为控制端时的键盘转发没有实测。
- 单独按下修饰键（例如只按 Win 打开开始菜单）不会发送。中文等需要输入法的文字仍要用键盘面板的「输入法」页。
- 字符键按美式键盘位置对应，其他键盘布局下带修饰键的符号组合可能不一致。
- 鼠标滚轮在观看端仍是缩放画面。2.3.6、2.3.7 记录里的其他未覆盖项仍然有效。
