# RDesk 远控操作弹层设计 QA

## 对照目标

- source visual truth path: `/var/folders/r3/hm8zwbj90g9bzx77pn1vgsp80000gn/T/codex-clipboard-126c8934-4b17-4f45-8d15-cd97d870e608.png`
- implementation screenshot path: `docs/screenshots/qa/remote-action-sheet-build14.png`
- combined comparison path: `docs/screenshots/qa/remote-action-sheet-comparison-build14.png`
- viewport: 390 × 844 CSS px，devicePixelRatio 1
- source pixels: 1320 × 2868；为全屏对照归一化到 390 × 844
- implementation pixels: 390 × 844；无需额外缩放
- state: 深色主题、竖屏、会话内「操作」弹层初始位置

## Findings

没有可执行的 P0、P1 或 P2 差异。

- 已接受的产品差异：参考图弹层约占屏幕高度 82%，本实现按用户要求缩短为 64%。
  首屏固定保留退出远控、仅观看、指针模式、旋转画面和高频操作；剪贴板及更多功能
  在同一弹层内部继续滚动，不增加第二套控制面。
- 已接受的证据差异：实现截图的远控画面背景为视觉测试底图，QA 聚焦对象为弹层本身；
  蒙层、圆角、操作区层级和底部贴边状态均按相同全屏视口对照。
- P3：低频「更多」入口不在 64% 高度的首屏内，需要一次上滑。该取舍来自“弹层太高”
  的明确反馈，且核心操作和剪贴板仍在首屏可见，因此不阻塞本次验收。

## Required Fidelity Surfaces

- Fonts and typography: 中文使用系统无衬线风格，标题、分组标签、主副文案层级清楚；
  最终截图已加载真实中文字体，未使用测试环境方块字形。字号、字重和行高与参考图同类。
- Spacing and layout rhythm: 16px 左右页边距、8px 快捷卡间距、14–16px 卡片圆角，
  分组间距和列表分隔线保持一致；64% 高度是有意收缩，不是裁切错误。
- Colors and visual tokens: 使用现有 RDesk 深色令牌；背景、卡片、次级文字和红色退出态
  与参考图的语义一致，文字和图标对比度可读。
- Image quality and asset fidelity: 界面没有需要替换的图片资产；所有可见功能图标均使用
  Material 图标字体，最终证据中边缘清晰，无占位图、表情符号或手绘图标。
- Copy and content: 参考图中的退出、仅观看、指针、旋转、滚动、删除、回车、唤醒、
  剪贴板、画质、显示器和文件传输均保留；新增电脑键盘、控制设置、网络状态，且仅展示
  当前端到端确实可用的能力。

## Comparison Evidence

- Full-view comparison: `docs/screenshots/qa/remote-action-sheet-comparison-build14.png` 同时放置
  参考图与 390 × 844 实现截图，可见弹层高度显著降低，顶部四项和列表卡片视觉语言一致。
- Focused region comparison: 顶部快捷区、操作卡和剪贴板卡在全尺寸合并图中均可清晰阅读，
  未发现需要额外放大的字体、图标或资源细节，因此不另做局部裁切。

## Comparison History

- 有效对照第 1 轮：未发现 P0/P1/P2；没有因视觉发现而修改实现，直接通过。
- 一张早期测试截图因 Flutter 测试字体未加载而出现方块字形，属于无效证据，已丢弃；
  重新加载真实中文字体与 Material Icons 后生成上述最终证据，不计为设计修复轮次。

## Implementation Checklist

- [x] 390 × 844 同视口渲染
- [x] 源图与实现图归一化后合并对照
- [x] 核对字体、间距、色彩、图标和文案
- [x] 确认弹层内容可内部滚动且核心操作首屏可见
- [x] 保留最终视觉证据

## 键盘界面补充 QA

### 对照目标

- source visual truth path: `/Users/qsw/work/project/rdesk/截图/IMG_6154.PNG`
- normalized source path: `docs/screenshots/qa/remote-keyboard-source-normalized.png`
- implementation screenshot path: `docs/screenshots/qa/remote-keyboard-build14.png`
- combined comparison path: `docs/screenshots/qa/remote-keyboard-comparison-build14.png`
- viewport: 390 × 844 CSS px，devicePixelRatio 1
- source pixels: 1320 × 2868；归一化到 390 × 844
- implementation pixels: 390 × 844；无需额外缩放
- state: 深色主题、竖屏、会话内「电脑键盘」标签选中、macOS 被控端能力

### Findings

最终对照没有可执行的 P0、P1 或 P2 差异。

- 已接受的产品差异：参考图提供 Control、Shift、Option、Command 等任意组合模式，
  当前传输链路只完整实现 macOS 的全选、复制、粘贴、剪切、撤销和重做，因此实现
  直接展示这六个真实动作，不展示尚不能端到端执行的任意修饰键组合。
- 已接受的证据差异：参考图背景是真实 macOS 远端画面，实现证据使用稳定的视觉测试
  背景；对照聚焦同一状态的键盘区域，背景内容不作为差异判断依据。
- P3：快捷操作采用一行紧凑中文按钮，参考图采用英文修饰键。实现更明确地表达当前
  可执行能力，也避免恢复已移除的静态「快捷键」能力声明。

### Required Fidelity Surfaces

- Fonts and typography: 最终截图加载真实 OPPO Sans 中文字体和 Material Icons；标签、
  主键区、功能键均无缺字或方框，字重和字号在 390px 宽度下清晰可读。
- Spacing and layout rhythm: 键盘弹层由首轮 68% 收缩至竖屏 50%，顶部标签与关闭按钮
  合并成参考图式单行结构；38px 键高、5px 行距及错位字母行形成稳定的键盘节奏。
- Colors and visual tokens: 沿用 RDesk 的深色背景、灰色键帽、白色前景和选中标签令牌，
  与参考图的暗色键盘层级一致，所有文字和按键边界保持足够对比度。
- Image quality and asset fidelity: 键盘不依赖额外图片资产；关闭图标使用 Material Icons，
  最终 1:1 截图边缘清晰，不含表情符号、占位图或手绘图标。
- Copy and content: 同时提供「输入法 / 电脑键盘」、字母、数字、Shift、Space、Enter、
  删除和 macOS 已实现快捷动作；未显示 Android 或未知系统不能执行的桌面能力。

### Comparison Evidence

- Full-view comparison: `docs/screenshots/qa/remote-keyboard-comparison-build14.png` 将 390 × 844
  参考图和实现图横向并排，可见弹层高度、顶部标签、关闭入口、键帽网格和底部功能区
  均处于同类密度和层级。
- Focused region comparison: 键盘区域占合并图下半屏且全部标签在原始尺寸下可读，主键区、
  顶部功能键和底部快捷动作均已在同一输入中清晰呈现，因此无需另做局部放大。

### Comparison History

- 第 1 轮：发现 P2 字形问题，macOS `⌘` 在测试字体下显示为方框；已将按钮改为
  「全选、复制、粘贴、剪切、撤销、重做」，重新截图后缺字消失。
- 第 2 轮：发现 P2 比例与结构差异，弹层占 68% 且多出独立「键盘」标题行；已收缩为
  竖屏 50%，并将「输入法 / 电脑键盘」标签与关闭按钮合并为单行。修正后键盘区域
  与参考图的下半屏结构一致。
- 第 3 轮：发现 P2 快捷动作末项需横向滚动才可见；已将六个按钮压缩为 55px，最终
  390px 视口内全部完整显示。
- 第 4 轮：最终并排复核未发现新的 P0/P1/P2，视觉验收通过。

### Implementation Checklist

- [x] 底部「键盘」直接进入新键盘界面
- [x] 「输入法 / 电脑键盘」标签可切换
- [x] 完整主键区、删除、回车和真实 macOS 快捷动作可操作
- [x] 390 × 844 同视口渲染并与源图合并对照
- [x] 修复所有 P0/P1/P2 并保留最终证据

final result: passed
