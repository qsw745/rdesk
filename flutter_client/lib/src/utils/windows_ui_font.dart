import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Windows interface font.
///
/// Microsoft YaHei ships in Light, Regular and Bold only, and Flutter draws
/// text without hinting, so the Bold face fills in dense characters (置, 制,
/// 输) at heading sizes. Loading the Regular face alone under its own family
/// name means emphasis is drawn as a moderate synthetic bold of that face
/// instead of the heavy Bold.
abstract final class WindowsUiFont {
  static const family = 'RdUiSans';

  /// Regular Microsoft YaHei, by file name inside the system font folder.
  static const _candidates = ['msyh.ttc', 'msyh.ttf'];

  static bool _loaded = false;

  /// True once [family] can be used; until then the system family applies.
  static bool get isLoaded => _loaded;

  @visibleForTesting
  static set debugLoaded(bool value) => _loaded = value;

  /// Loads the face if this is Windows and the file is there. Never throws:
  /// without it the interface simply keeps the system family.
  static Future<void> load() async {
    if (kIsWeb || !Platform.isWindows || _loaded) return;
    final root = Platform.environment['WINDIR'] ??
        Platform.environment['SystemRoot'] ??
        r'C:\Windows';
    for (final name in _candidates) {
      final file = File('$root\\Fonts\\$name');
      try {
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
        _loaded = true;
        return;
      } on Object catch (error) {
        // Everything, errors included: this runs before the first frame,
        // and a font is never worth an application that does not start.
        debugPrint('[RDesk] interface font not loaded: ${error.runtimeType}');
      }
    }
  }
}
