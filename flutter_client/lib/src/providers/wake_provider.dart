import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wake.dart';
import '../services/wake_api.dart';
import '../services/wake_agent_channel.dart';
import '../services/windows_wake_service.dart';

class WakeProvider extends ChangeNotifier {
  final WakeApi api;
  final WakeAgentChannel agent;
  final WindowsWakeService? windows;
  WakeProvider({required this.api, required this.agent, this.windows});
  String? _userId, _server;
  int _generation = 0;
  bool _disposed = false, _visible = false, _refreshing = false;
  Future<void> _nativeTail = Future.value();
  Timer? _timer;
  List<WakeTarget> targets = [];
  List<WakeAgent> agents = [];
  Map<String, List<WakeRequest>> history = {};
  WakeAgentStatus helper = const WakeAgentStatus();
  bool busy = false;
  String? error;
  bool get loggedIn => _userId != null;
  String? get userId => _userId;
  bool _current(int gen) => !_disposed && gen == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _native(Future<void> Function() action) {
    final next = _nativeTail.then((_) => action());
    _nativeTail = next.catchError((Object _) {});
    return next;
  }

  String _key(Uri uri, String user) =>
      'rdesk.wake.helper.${sha256.convert(utf8.encode('$uri|$user'))}';

  Future<void> bindAccount(String? userId, String server) async {
    if (_userId == userId && _server == server) return;
    final previous = _server != null;
    _userId = userId;
    _server = server;
    final gen = ++_generation;
    _timer?.cancel();
    targets = [];
    agents = [];
    history = {};
    busy = false;
    error = null;
    helper = const WakeAgentStatus();
    await windows?.stop();
    try {
      if (previous) await agent.stop();
      final endpoint = (await api.endpoint()).toString();
      await _native(() async {
        final status = await agent.status();
        if (!_current(gen)) return;
        if (previous ||
            userId == null ||
            status.ownerId != userId ||
            status.endpoint != endpoint) {
          await agent.stop();
        } else {
          helper = status;
        }
      });
      if (!_current(gen)) return;
      if (userId != null) await windows?.resume(userId);
    } catch (_) {
      if (_current(gen)) error = '开机助手状态读取失败，请重新启用';
    }
    if (_current(gen)) {
      _notify();
      if (_visible) unawaited(refresh());
    }
  }

  /// Called before account credentials are removed. Generation changes immediately.
  Future<void> stopForAccountExit() async {
    ++_generation;
    _userId = null;
    _timer?.cancel();
    targets = [];
    agents = [];
    history = {};
    busy = false;
    helper = const WakeAgentStatus();
    await windows?.stop();
    await agent.stop();
    await _native(agent.stop);
  }

  void setVisible(bool visible) {
    _visible = visible;
    _timer?.cancel();
    if (visible) unawaited(refresh());
  }

  void _schedule() {
    _timer?.cancel();
    if (_visible && loggedIn && !_disposed) {
      final active = history.values.expand((v) => v).any((r) => r.active);
      _timer =
          Timer(Duration(seconds: active ? 2 : 15), () => unawaited(refresh()));
    }
  }

  Future<void> refresh() async {
    if (!loggedIn || _refreshing || _disposed) {
      _schedule();
      return;
    }
    _refreshing = true;
    final gen = _generation;
    WakeApi? scoped;
    try {
      scoped = await api.scoped();
      if (!_current(gen)) return;
      final newTargets = await scoped.targets();
      final newAgents = await scoped.agents();
      final histories = <String, List<WakeRequest>>{};
      for (final target in newTargets) {
        if (!_current(gen)) return;
        histories[target.id] = await scoped.history(target.id);
      }
      final status = await agent.status();
      if (!_current(gen)) return;
      targets = newTargets;
      agents = newAgents;
      history = histories;
      helper = status;
      error = null;
    } catch (e) {
      if (_current(gen)) error = _message(e);
    } finally {
      scoped?.close();
      _refreshing = false;
      _schedule();
      _notify();
    }
  }

  String _message(Object e) => e is WakeApiException
      ? e.message
      : e is StateError
          ? e.message
          : '操作失败，请检查网络、权限后重试';

  Future<bool> _mutate(Future<void> Function(WakeApi, int) action) async {
    if (busy || !loggedIn) return false;
    busy = true;
    error = null;
    _notify();
    final gen = _generation;
    WakeApi? scoped;
    try {
      scoped = await api.scoped();
      if (!_current(gen)) return false;
      await action(scoped, gen);
      return _current(gen);
    } catch (e) {
      if (_current(gen)) error = _message(e);
      return false;
    } finally {
      scoped?.close();
      if (_current(gen)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> enableHelper(String name) => _mutate((scoped, gen) async {
        final user = _userId!;
        await agent.prepare();
        if (!_current(gen)) return;
        final endpoint = await scoped.endpoint();
        final prefs = await SharedPreferences.getInstance();
        if (!_current(gen)) return;
        final key = _key(endpoint, user);
        final oldId = prefs.getString(key);
        await _native(agent.stop);
        if (!_current(gen)) return;
        WakeEnrollment? enrollment;
        bool created = false;
        if (oldId != null) {
          try {
            enrollment = await scoped.enableAgent(oldId, name);
          } on WakeApiException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
        }
        if (enrollment == null) {
          if (!_current(gen)) return;
          enrollment = await scoped.createAgent(name);
          created = true;
        }
        final registered = enrollment;
        Future<void> rollback() => created
            ? scoped.revokeAgent(registered.id)
            : scoped.stopAgent(registered.id);
        try {
          if (!_current(gen)) return;
          await prefs.setString(key, registered.id);
          await _native(() async {
            if (!_current(gen)) return;
            await agent.start(
                endpoint: endpoint.toString(),
                ownerId: user,
                agentId: registered.id,
                token: registered.token);
            if (!_current(gen)) await agent.stop();
          });
          if (_current(gen)) helper = await agent.status();
        } catch (_) {
          if (_current(gen)) await _native(agent.stop);
          await rollback();
          rethrow;
        } finally {
          if (!_current(gen)) await rollback();
        }
        if (_current(gen)) await refresh();
      });
  Future<bool> disableHelper() => _mutate((scoped, gen) async {
        final endpoint = await scoped.endpoint();
        final user = _userId!;
        await _native(agent.stop);
        final prefs = await SharedPreferences.getInstance();
        final key = _key(endpoint, user);
        final id = prefs.getString(key);
        if (id != null) {
          try {
            await scoped.stopAgent(id);
          } on WakeApiException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
        }
        if (_current(gen)) {
          helper = const WakeAgentStatus();
          await refresh();
        }
      });
  Future<bool> wake(WakeTarget target) => _mutate((scoped, gen) async {
        if (target.online ||
            !target.agentOnline ||
            (history[target.id]?.any((r) => r.active) ?? false)) {
          return;
        }
        final request = await scoped.requestWake(target.id);
        if (_current(gen)) {
          history[target.id] = [request, ...?history[target.id]];
          _schedule();
        }
      });
  Future<bool> remove(WakeTarget target) => _mutate((scoped, gen) async {
        await scoped.deleteTarget(target.id);
        if (_current(gen)) await refresh();
      });
  Future<bool> rebind(WakeTarget target, String agentId) =>
      _mutate((scoped, gen) async {
        await scoped.updateTarget(target.id,
            name: target.name, mac: target.mac, agentId: agentId);
        if (_current(gen)) await refresh();
      });
  Future<bool> removeHelper(WakeAgent selected) => _mutate((scoped, gen) async {
        if (helper.agentId == selected.id) await _native(agent.stop);
        await scoped.revokeAgent(selected.id);
        if (_current(gen)) await refresh();
      });
  Future<bool> enrollWindows(
          {required String deviceId,
          required String name,
          required String mac,
          required String agentId}) =>
      _mutate((_, gen) async {
        if (windows == null) throw StateError('请在要开机的 Windows 电脑上完成配置');
        await windows!.enroll(
            userId: _userId!,
            deviceId: deviceId,
            name: name,
            mac: mac,
            agentId: agentId);
        if (_current(gen)) await refresh();
      });
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    unawaited(windows?.dispose() ?? Future.value());
    api.close();
    super.dispose();
  }
}
