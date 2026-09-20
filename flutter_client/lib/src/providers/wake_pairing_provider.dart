import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/wake_pairing.dart';
import '../services/wake_api.dart';
import '../services/wake_pairing_vault.dart';

enum PairingPhase {
  idle,
  checking,
  waiting,
  confirmed,
  claiming,
  paired,
  expired,
  failed
}

class WakePairingProvider extends ChangeNotifier {
  final WakeApi api;
  final WakePairingVault vault;
  final Future<void> Function(String user)? onPaired;
  final DateTime Function() now;
  WakePairingProvider(
      {required this.api,
      required this.vault,
      this.onPaired,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  PairingPhase phase = PairingPhase.idle;
  WakePairingSession? session;
  String? error, targetId;
  String? _user, _server, _candidate, _deviceId;
  Uri? _endpoint;
  WakeApi? _scoped;
  Timer? _timer;
  int _generation = 0;
  bool _visible = false, _busy = false, _disposed = false, _restored = false;
  bool get busy => _busy;
  int get secondsRemaining => session == null
      ? 0
      : max(
          0,
          ((session!.expiresAtMs - now().millisecondsSinceEpoch) / 1000)
              .ceil());
  bool _current(int g) => !_disposed && g == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void bindAccount(String? user, String server) {
    if (user == _user && server == _server) return;
    ++_generation;
    _timer?.cancel();
    _scoped?.close();
    _scoped = null;
    _user = user;
    _server = server;
    _endpoint = null;
    _candidate = null;
    _deviceId = null;
    session = null;
    targetId = null;
    error = null;
    phase = PairingPhase.idle;
    _busy = false;
    _restored = false;
    // ProxyProvider may bind during build. Notify after that build completes.
    scheduleMicrotask(_notify);
    if (_visible && user != null) unawaited(restore());
  }

  void setVisible(bool value) {
    _visible = value;
    _timer?.cancel();
    if (value && _user != null) {
      if (!_restored) {
        unawaited(restore());
      } else {
        unawaited(poll());
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_visible &&
        !_disposed &&
        session != null &&
        phase != PairingPhase.paired &&
        phase != PairingPhase.expired &&
        phase != PairingPhase.failed) {
      _timer = Timer(const Duration(seconds: 2), () => unawaited(poll()));
    }
  }

  Future<bool> _scope(int gen) async {
    if (_scoped != null) return _current(gen);
    final scoped = await api.scoped();
    final endpoint = await scoped.endpoint();
    if (!_current(gen)) {
      scoped.close();
      return false;
    }
    _scoped = scoped;
    _endpoint = endpoint;
    return true;
  }

  Future<void> restore() async {
    if (_busy || _user == null || _restored) return;
    final gen = _generation;
    _busy = true;
    try {
      if (!await _scope(gen)) return;
      final saved = await vault.read(_user!, _endpoint!);
      if (!_current(gen)) return;
      _restored = true;
      if (saved != null) {
        session = WakePairingSession.fromJson(
            Map<String, dynamic>.from(saved['session'] as Map));
        _deviceId = saved['device_id'] as String;
        _candidate = saved['candidate_token'] as String?;
        phase = PairingPhase.waiting;
      } else {
        final known = await vault.enrollment(_user!, _endpoint!);
        if (!_current(gen)) return;
        if (known != null) {
          targetId = known.id;
          await _scoped!.targetHeartbeat(known.id, known.token);
          if (!_current(gen)) return;
          phase = PairingPhase.paired;
          await onPaired?.call(_user!);
        }
      }
    } catch (e) {
      if (_current(gen)) {
        error = e is WakeApiException ? e.message : '无法读取安全凭据，请重试';
        phase = PairingPhase.failed;
      }
    } finally {
      if (_current(gen)) {
        _busy = false;
        _notify();
      }
    }
    if (_current(gen) && session != null) await poll();
  }

  Future<void> start(
      {required String name,
      required String deviceId,
      required String mac}) async {
    if (_busy || _user == null) return;
    if (_candidate != null) {
      await poll();
      return;
    }
    final gen = _generation;
    _busy = true;
    error = null;
    phase = PairingPhase.checking;
    _notify();
    try {
      if (!await _scope(gen)) return;
      if (session != null) {
        await _scoped!.cancelPairing(session!).catchError((Object _) {});
      }
      final created = await _scoped!
          .createPairing(name: name, deviceId: deviceId, mac: mac);
      if (!_current(gen)) return;
      session = created;
      _deviceId = deviceId;
      _candidate = null;
      targetId = null;
      await _persist();
      if (!_current(gen)) return;
      _restored = true;
      phase = PairingPhase.waiting;
    } catch (e) {
      if (_current(gen)) {
        phase = PairingPhase.failed;
        error = _message(e);
      }
    } finally {
      if (_current(gen)) {
        _busy = false;
        _notify();
        _schedule();
      }
    }
  }

  Future<void> _persist() => vault.save(_user!, _endpoint!, {
        'session': session!.toJson(),
        'device_id': _deviceId,
        'candidate_token': _candidate
      });
  Future<void> poll() async {
    if (_busy ||
        session == null ||
        _user == null ||
        phase == PairingPhase.paired) {
      return;
    }
    final gen = _generation;
    _busy = true;
    final scoped = _scoped!;
    final user = _user!;
    final endpoint = _endpoint!;
    try {
      if (secondsRemaining == 0) {
        if (!await _recover(gen, scoped, user, endpoint)) {
          if (_current(gen)) {
            phase = PairingPhase.expired;
            error = '配对码已过期，请重新生成';
          }
        }
        return;
      }
      final status = await scoped.pairingStatus(session!);
      if (!_current(gen)) return;
      if (status['state'] == 'confirmed' || status['state'] == 'claimed') {
        phase = PairingPhase.claiming;
        _notify();
        _candidate ??=
            List<int>.generate(32, (_) => Random.secure().nextInt(256))
                .map((v) => v.toRadixString(16).padLeft(2, '0'))
                .join();
        // Never send a credential that cannot be recovered after a crash.
        await _persist();
        if (!_current(gen)) return;
        final id = await scoped.claimPairing(session!, _candidate!);
        if (!_current(gen)) return;
        await _finish(gen, user, endpoint, id);
      } else if (status['state'] == 'pending') {
        phase = PairingPhase.waiting;
        error = null;
      } else {
        throw const WakeApiException('invalid_response', '配对状态无法识别');
      }
    } on WakeApiException catch (e) {
      if (!_current(gen)) return;
      if (e.statusCode == 404 || e.statusCode == 410) {
        try {
          if (!await _recover(gen, scoped, user, endpoint) && _current(gen)) {
            phase = PairingPhase.expired;
            error = '配对已失效，请重新生成';
          }
        } catch (e) {
          if (_current(gen)) error = _message(e);
        }
      } else {
        error = e.message;
        if (e.statusCode == 401 || e.statusCode == 409) {
          phase = PairingPhase.failed;
          _timer?.cancel();
        }
      }
    } catch (e) {
      if (_current(gen)) {
        error = _message(e);
        phase = PairingPhase.failed;
      }
    } finally {
      if (_current(gen)) {
        _busy = false;
        _notify();
        _schedule();
      }
    }
  }

  Future<bool> _recover(
      int gen, WakeApi scoped, String user, Uri endpoint) async {
    if (_candidate == null) return false;
    final targets = await scoped.targets();
    if (!_current(gen)) return false;
    for (final target in targets.where((t) => t.deviceId == _deviceId)) {
      await scoped.targetHeartbeat(target.id, _candidate!);
      if (!_current(gen)) return false;
      await _finish(gen, user, endpoint, target.id);
      return true;
    }
    return false;
  }

  Future<void> _finish(int gen, String user, Uri endpoint, String id) async {
    await vault.promote(user, endpoint, id, _candidate!);
    if (!_current(gen)) return;
    await vault.clear(user, endpoint);
    if (!_current(gen)) return;
    targetId = id;
    phase = PairingPhase.paired;
    error = null;
    _timer?.cancel();
    await onPaired?.call(user);
  }

  /// Only call after the user has explicitly removed the old server binding.
  Future<void> resetRemovedBinding() async {
    final gen = ++_generation;
    _timer?.cancel();
    if (_user != null && _endpoint != null)
      await vault.clear(_user!, _endpoint!);
    if (!_current(gen)) return;
    session = null;
    targetId = null;
    _candidate = null;
    _deviceId = null;
    error = null;
    phase = PairingPhase.idle;
    _busy = false;
    _notify();
  }

  Future<void> cancelForExit() async {
    final scoped = _scoped;
    final s = session;
    ++_generation;
    _timer?.cancel();
    _user = null;
    _busy = false;
    session = null;
    targetId = null;
    phase = PairingPhase.idle;
    _candidate = null;
    try {
      if (scoped != null && s != null) await scoped.cancelPairings();
    } catch (_) {/* TTL still bounds offline cancellation. */} finally {
      scoped?.close();
      _scoped = null;
    }
  }

  String _message(Object e) =>
      e is WakeApiException ? e.message : '安全保存或恢复配对失败，请重试';
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _scoped?.close();
    super.dispose();
  }
}
