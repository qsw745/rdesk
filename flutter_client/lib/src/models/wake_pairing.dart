import 'dart:convert';

class WakePairingCode {
  final String? id, proof, manualCode;
  const WakePairingCode.qr(this.id, this.proof) : manualCode = null;
  const WakePairingCode.manual(this.manualCode)
      : id = null,
        proof = null;
  factory WakePairingCode.parse(String text) {
    if (text.length > 512) throw const FormatException('请扫描 RDesk 电脑上的配对二维码');
    Object? value;
    try {
      value = jsonDecode(text);
    } catch (_) {
      throw const FormatException('请扫描 RDesk 电脑上的配对二维码');
    }
    if (value is! Map ||
        value.length != 4 ||
        value['type'] != 'rdesk-wake-pair' ||
        value['version'] != 1 ||
        value['id'] is! String ||
        value['proof'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id'] as String) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['proof'] as String)) {
      throw const FormatException('二维码格式不正确或版本不支持');
    }
    return WakePairingCode.qr(value['id'] as String, value['proof'] as String);
  }
  Map<String, Object?> get resolveBody => manualCode != null
      ? {'manual_code': manualCode}
      : {'id': id, 'qr_proof': proof};
  Map<String, Object?> get confirmBody =>
      manualCode != null ? {'manual_code': manualCode} : {'qr_proof': proof};
  String get qrText => jsonEncode(
      {'type': 'rdesk-wake-pair', 'version': 1, 'id': id, 'proof': proof});
}

class WakePairingSession {
  final String id, qrProof, desktopProof, manualCode;
  final int expiresAtMs;
  const WakePairingSession(
      {required this.id,
      required this.qrProof,
      required this.desktopProof,
      required this.manualCode,
      required this.expiresAtMs});
  factory WakePairingSession.fromJson(Map<String, dynamic> j) =>
      WakePairingSession(
          id: j['id'] as String,
          qrProof: j['qr_proof'] as String,
          desktopProof: j['desktop_proof'] as String,
          manualCode: j['manual_code'] as String,
          expiresAtMs: (j['expires_at_ms'] as num).toInt());
  Map<String, Object?> toJson() => {
        'id': id,
        'qr_proof': qrProof,
        'desktop_proof': desktopProof,
        'manual_code': manualCode,
        'expires_at_ms': expiresAtMs
      };
  String get qrText => WakePairingCode.qr(id, qrProof).qrText;
}
