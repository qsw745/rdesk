/// Matches the IPv4 / optional-port addresses supported by the native bridge.
bool isDirectDeviceAddress(String value) {
  final parts = value.split(':');
  if (parts.length > 2) return false;
  final octets = parts.first.split('.');
  if (octets.length != 4 ||
      octets
          .any((v) => !RegExp(r'^\d{1,3}$').hasMatch(v) || int.parse(v) > 255))
    return false;
  if (parts.length == 2) {
    final port = int.tryParse(parts.last);
    if (port == null || port < 1 || port > 65535) return false;
  }
  return true;
}
