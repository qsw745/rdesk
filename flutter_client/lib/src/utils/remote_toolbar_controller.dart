import 'dart:async';

import 'package:flutter/foundation.dart';

class RemoteToolbarController extends ChangeNotifier {
  RemoteToolbarController({
    this.autoHideDelay = const Duration(seconds: 5),
  });

  final Duration autoHideDelay;
  Timer? _hideTimer;
  bool _visible = true;
  bool _autoHide = false;

  bool get visible => _visible;
  bool get autoHide => _autoHide;

  void setAutoHide(bool enabled) {
    if (_autoHide == enabled) return;
    _autoHide = enabled;
    if (enabled) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
      _hideTimer = null;
    }
    notifyListeners();
  }

  void markInteraction() {
    if (!_autoHide || !_visible) return;
    _scheduleHide();
  }

  void show() {
    final changed = !_visible;
    _visible = true;
    if (_autoHide) _scheduleHide();
    if (changed) notifyListeners();
  }

  void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(autoHideDelay, hide);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}
