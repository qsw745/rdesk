class AppConstants {
  static const String appName = '随控';
  static const String version = '2.1.0';
  // 普通版唯一的官方服务配置，不从用户偏好或可编辑文件读取。
  // 同域名迁机使用 DNS；更换域名需修改此配置并发布经过本地验证的客户端。
  // 必须保持 HTTPS，WebSocket 自动使用 WSS。
  static const String defaultSignalingServer = 'https://qisw.top';
  static const String defaultRelayServer = defaultSignalingServer;
  static const int deviceIdLength = 9;
  static const int tempPasswordLength = 6;
}
