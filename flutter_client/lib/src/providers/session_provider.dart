import 'package:flutter/foundation.dart';
import '../models/session.dart';

class SessionProvider extends ChangeNotifier {
  SessionInfo? _currentSession;
  Uint8List? _currentFrame;
  int _frameWidth = 0;
  int _frameHeight = 0;
  bool _controlEnabled = true;

  SessionInfo? get currentSession => _currentSession;
  Uint8List? get currentFrame => _currentFrame;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  bool get controlEnabled => _controlEnabled;

  void setSession(SessionInfo session) {
    _currentSession = session;
    notifyListeners();
  }

  void updateFrame(Uint8List frameData, int width, int height) {
    _currentFrame = frameData;
    _frameWidth = width;
    _frameHeight = height;
    notifyListeners();
  }

  void updateLatency(int latencyMs) {
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(latencyMs: latencyMs);
      notifyListeners();
    }
  }

  void toggleControl() {
    _controlEnabled = !_controlEnabled;
    notifyListeners();
  }

  void clearSession() {
    _currentSession = null;
    _currentFrame = null;
    _frameWidth = 0;
    _frameHeight = 0;
    notifyListeners();
  }
}
