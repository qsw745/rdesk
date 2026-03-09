<p align="center">
  <img src="docs/logo.png" alt="RDesk Logo" width="120" height="120" />
</p>

<h1 align="center">RDesk 远程桌面</h1>

<p align="center">
  <strong>安全、高效、跨平台的远程控制软件</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#系统架构">系统架构</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#项目结构">项目结构</a> •
  <a href="#技术栈">技术栈</a> •
  <a href="#开发指南">开发指南</a>
</p>

---

## 简介

RDesk 是一款开源的跨平台远程桌面控制软件，支持 **电脑与电脑**、**电脑与手机**、**手机与手机** 之间的远程连接，可在 Windows、macOS、Linux、Android、iOS 等多个操作系统之间自由互控。

核心引擎使用 **Rust** 编写，保证极致的性能和安全性；客户端界面基于 **Flutter** 构建，一套代码覆盖全平台。采用 **P2P 直连 + 中继回退** 的混合连接策略，在保障连接稳定性的同时实现最低延迟。

## 功能特性

### 远程控制
- 🖥️ **屏幕共享** — 实时查看和操控远程设备屏幕
- 🖱️ **鼠标与键盘** — 支持鼠标移动、点击、滚轮以及完整键盘输入
- 📱 **触屏手势** — 手机端支持多点触控手势转发
- 🖼️ **多显示器** — 支持多屏幕切换与独立操控
- 🎚️ **自适应画质** — 根据网络状况动态调节码率，自动平衡画质与流畅度

### 数据传输
- 📁 **文件传输** — 双向文件传输，支持断点续传与 LZ4 压缩
- 📋 **剪贴板同步** — 自动同步文本、HTML 和图片剪贴板内容
- 💬 **文字聊天** — 会话内即时文字消息

### 安全性
- 🔐 **端到端加密** — 基于 Noise 协议（XX 模式）的端到端加密，中继服务器无法解密数据
- 🛡️ **双层加密** — QUIC/TLS 传输加密 + Noise 端到端加密
- 🔑 **设备认证** — 9 位数字设备 ID + 临时/永久密码认证
- 🔄 **前向保密** — 每次会话使用独立的临时密钥交换

### 网络连接
- 🌐 **P2P 直连** — 支持 NAT 穿透 / UDP 打洞，优先使用点对点直连
- 🔀 **中继回退** — P2P 失败时自动切换至中继服务器，保障连接可用性
- ⚡ **QUIC 协议** — 基于 QUIC 的多路复用传输，低延迟、抗丢包、支持连接迁移
- 📡 **NAT 检测** — 自动识别 NAT 类型（完全锥形、受限锥形、对称型等）

## 支持平台

| 平台 | 被控（屏幕共享） | 主控（远程操控） | 状态 |
|------|:-:|:-:|------|
| **Windows** | ✅ | ✅ | DXGI 屏幕捕获 + SendInput 输入模拟 |
| **macOS** | ✅ | ✅ | ScreenCaptureKit + CGEvent 输入模拟 |
| **Linux** | ✅ | ✅ | X11/Wayland 捕获 + evdev 输入模拟 |
| **Android** | ✅ | ✅ | MediaProjection + AccessibilityService |
| **iOS** | ⚠️ 仅查看 | ✅ | ReplayKit（系统限制，不支持输入注入） |

## 系统架构

```
┌─────────────────────┐         ┌──────────────────┐         ┌─────────────────────┐
│    主控端 (Viewer)    │         │    基础设施服务     │         │   被控端 (Host)      │
│                     │         │                  │         │                     │
│  ┌───────────────┐  │  UDP    │  ┌────────────┐  │  UDP    │  ┌───────────────┐  │
│  │  Flutter UI   │  │ ──────> │  │  信令服务器  │  │ <────── │  │   Rust 引擎   │  │
│  └───────┬───────┘  │ 注册/   │  │ (Signaling)│  │  注册/  │  └───────┬───────┘  │
│          │ FFI      │ 发现    │  └─────┬──────┘  │  发现   │          │          │
│  ┌───────┴───────┐  │         │        │         │         │  ┌───────┴───────┐  │
│  │  Rust Bridge  │  │         │  ┌─────┴──────┐  │         │  │ 屏幕捕获+编码  │  │
│  └───────┬───────┘  │         │  │  中继服务器  │  │         │  │ 输入模拟      │  │
│          │          │         │  │  (Relay)   │  │         │  └───────────────┘  │
│  ┌───────┴───────┐  │  QUIC   │  └────────────┘  │  QUIC   │                     │
│  │ 解码 + 渲染    │  │ ═══════════════════════════════════ │                     │
│  └───────────────┘  │     P2P 直连 (或通过中继转发)         │                     │
└─────────────────────┘                                      └─────────────────────┘

    QUIC 多路复用流：
    ├── Stream 0: 控制通道（会话管理、输入事件、剪贴板）
    ├── Stream 1: 视频帧流
    ├── Stream 2: 文件传输
    └── Stream 3: 聊天消息
```

## 项目结构

```
rdesk/
├── Cargo.toml                   # Rust Workspace 根配置
├── proto/                       # Protobuf 协议定义
│   ├── message.proto            #   会话消息（视频帧、输入、剪贴板、文件传输、聊天）
│   └── rendezvous.proto         #   信令消息（注册、打洞、中继）
│
├── crates/                      # Rust 模块
│   ├── rdesk_common/            #   公共类型、配置、设备ID、密码、Protobuf
│   ├── rdesk_crypto/            #   加密层：Noise_XX 握手、密钥管理、认证
│   ├── rdesk_net/               #   网络层：P2P 打洞、QUIC 传输、中继客户端
│   ├── rdesk_core/              #   核心引擎：屏幕捕获、编解码、输入模拟、剪贴板、文件传输
│   ├── rdesk_bridge/            #   Flutter FFI 桥接层（flutter_rust_bridge）
│   └── rdesk_server/            #   信令 + 中继服务器
│
├── flutter_client/              # Flutter 跨平台客户端
│   ├── lib/
│   │   ├── main.dart            #   应用入口
│   │   ├── app.dart             #   MaterialApp 配置
│   │   └── src/
│   │       ├── screens/         #   页面：首页、远程桌面、文件管理、聊天、设置
│   │       ├── widgets/         #   组件：远程画布、工具栏、设备ID卡片
│   │       ├── providers/       #   状态管理（Provider）
│   │       ├── models/          #   数据模型
│   │       ├── services/        #   服务层
│   │       └── utils/           #   工具：主题、路由、常量
│   ├── android/                 #   Android 平台配置
│   ├── ios/                     #   iOS 平台配置
│   ├── macos/                   #   macOS 平台配置
│   ├── windows/                 #   Windows 平台配置
│   └── linux/                   #   Linux 平台配置
│
└── scripts/                     # 构建与工具脚本
```

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **核心引擎** | Rust | 高性能、内存安全、零成本抽象 |
| **客户端 UI** | Flutter | 一套代码覆盖 5 个平台 |
| **FFI 桥接** | flutter_rust_bridge v2 | Rust ↔ Dart 自动绑定生成 |
| **传输协议** | QUIC (quinn) | 多路复用、拥塞控制、连接迁移 |
| **加密** | Noise_XX (snow) + QUIC/TLS | 端到端加密 + 传输加密 |
| **序列化** | Protocol Buffers (prost) | 高效二进制消息编码 |
| **视频编码** | VP9 (libvpx) | 免版税、高压缩率 |
| **屏幕捕获** | xcap + 平台原生 API | DXGI / ScreenCaptureKit / X11 |
| **状态管理** | Provider | Flutter 响应式状态管理 |
| **密码哈希** | Argon2 | 抗 GPU 暴力破解 |
| **密钥交换** | X25519 / Ed25519 | 现代椭圆曲线密码学 |

## 快速开始

### 环境要求

- **Rust** ≥ 1.75（安装：https://rustup.rs）
- **Flutter** ≥ 3.19（安装：https://flutter.dev）
- **Protobuf 编译器**（protoc）
- 平台开发工具：
  - macOS: Xcode
  - Linux: gcc, libx11-dev, libxcb-randr0-dev
  - Windows: Visual Studio Build Tools
  - Android: Android SDK + NDK
  - iOS: Xcode + CocoaPods

### 构建步骤

```bash
# 1. 克隆项目
git clone https://github.com/your-org/rdesk.git
cd rdesk

# 2. 编译 Rust 核心库
cargo build --workspace

# 3. 启动信令/中继服务器
cargo run -p rdesk_server -- --signaling-port 21116 --relay-port 21117

# 4. 进入 Flutter 客户端目录
cd flutter_client

# 5. 生成 Rust FFI 绑定
flutter_rust_bridge_codegen generate

# 6. 运行客户端
flutter run               # 当前平台
flutter run -d macos       # macOS 桌面
flutter run -d windows     # Windows 桌面
flutter run -d linux       # Linux 桌面
flutter run -d android     # Android 设备
flutter run -d ios         # iOS 设备
```

### 服务器部署

```bash
# 编译发布版本
cargo build -p rdesk_server --release

# 启动服务器（可自定义端口）
./target/release/rdesk-server \
  --bind 0.0.0.0 \
  --signaling-port 21116 \
  --relay-port 21117

# 需要在防火墙/安全组中开放以下端口：
#   UDP 21116 — 信令服务器
#   UDP 21117 — 中继服务器
```

## 连接流程

```
1. 两台设备启动 RDesk，各自获得 9 位设备 ID
2. 两台设备向信令服务器注册，保持心跳
3. 主控端输入被控端的设备 ID 和密码，发起连接请求
4. 信令服务器协调双方进行 NAT 打洞
5. 若打洞成功 → P2P 直连（最低延迟）
   若打洞失败 → 自动回退到中继服务器转发
6. 建立 QUIC 连接后，通过 Noise_XX 握手建立端到端加密
7. 密码验证通过后，会话正式建立
8. 开始屏幕共享、远程控制、文件传输等功能
```

## 安全设计

RDesk 在安全性上采用纵深防御策略：

| 威胁 | 防护措施 |
|------|----------|
| 网络窃听 | Noise_XX 端到端加密 + QUIC/TLS 传输加密 |
| 中间人攻击 | 服务器签名的公钥身份验证 |
| 中继窃听 | 端到端加密，中继只转发密文 |
| 暴力破解密码 | Argon2 哈希 + 登录频率限制（3 次失败后冷却 30 秒） |
| 重放攻击 | Noise 协议 nonce + QUIC 包序号 |
| 密钥泄露 | 临时 DH 密钥交换实现前向保密 |

## 开发指南

### Rust 模块依赖关系

```
rdesk_bridge (FFI 层，暴露给 Flutter)
    ├── rdesk_core    (核心引擎)
    │   ├── rdesk_net     (网络：P2P、QUIC、中继)
    │   ├── rdesk_crypto  (加密、认证)
    │   └── rdesk_common  (公共类型、Protobuf、配置)
    └── rdesk_common

rdesk_server (独立服务器二进制)
    ├── rdesk_net
    ├── rdesk_crypto
    └── rdesk_common
```

### 常用命令

```bash
# 编译检查
cargo check --workspace

# 运行测试
cargo test --workspace

# 格式化代码
cargo fmt --all

# 代码检查
cargo clippy --workspace

# 重新生成 Protobuf 代码
cargo build -p rdesk_common

# Flutter 代码格式化
cd flutter_client && dart format .
```

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

## 致谢

RDesk 的设计与实现参考了以下优秀的开源项目：

- [RustDesk](https://github.com/rustdesk/rustdesk) — Rust 远程桌面的先驱
- [quinn](https://github.com/quinn-rs/quinn) — Rust QUIC 协议实现
- [snow](https://github.com/mcginty/snow) — Noise 协议框架
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) — Flutter ↔ Rust FFI 桥接
- [xcap](https://github.com/nashaofu/xcap) — 跨平台屏幕捕获

---

<p align="center">
  <sub>用 Rust 和 Flutter 构建 ❤️ 安全高效的远程控制体验</sub>
</p>
