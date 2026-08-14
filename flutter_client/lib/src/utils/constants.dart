class AppConstants {
  static const String appName = 'RDesk 远程桌面';
  static const String version = '2.1.0';
  // 必须带 https://：远程画面与账号密码都经此地址传输，
  // 明文 HTTP 会让屏幕内容和登录凭据在网络上暴露。
  // WebSocket 会依据此协议自动切换到 wss（见 _tryWebSocketStream）。
  static const String defaultSignalingServer = 'https://qisw.top';
  static const String defaultRelayServer = 'https://qisw.top';
  static const int deviceIdLength = 9;
  static const int tempPasswordLength = 6;
}
