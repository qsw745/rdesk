/// The remote host's OS as far as viewer controls are concerned. Controls are
/// only offered for a platform whose host actually implements them.
enum RemotePeerPlatform { mac, windows, android, other }

RemotePeerPlatform remotePeerPlatformOf(String peerOs) {
  final value = peerOs.trim().toLowerCase();
  // `darwin` contains `win`, so it has to be matched first.
  if (value.contains('mac') || value.contains('darwin')) {
    return RemotePeerPlatform.mac;
  }
  if (value.contains('win')) return RemotePeerPlatform.windows;
  if (value.contains('android')) return RemotePeerPlatform.android;
  return RemotePeerPlatform.other;
}

extension RemotePeerPlatformKeys on RemotePeerPlatform {
  /// Esc, Tab, arrows and the edit shortcuts are implemented by this host.
  bool get hasDesktopKeys =>
      this == RemotePeerPlatform.mac || this == RemotePeerPlatform.windows;

  /// The host can restart and shut itself down on request.
  bool get hasPowerActions => this == RemotePeerPlatform.windows;
}
