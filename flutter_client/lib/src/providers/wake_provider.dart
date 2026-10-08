import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wake.dart';
import '../services/wake_api.dart';
import '../services/wake_agent_channel.dart';
import '../services/windows_wake_service.dart';
import '../utils/wake_target_group.dart';

class WakeProvider extends ChangeNotifier with WidgetsBindingObserver {
  final WakeApi api;
  final WakeAgentChannel agent;
  final WindowsWakeService? windows;
  WakeProvider({required this.api, required this.agent, this.windows}) {
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
  }
  String? _userId, _server;
  int _generation = 0;
  bool _disposed = false, _visible = false, _refreshing = false;
  bool _foreground = true;
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
  int get identityGeneration => _generation;
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

  /// Helper id and LAN only; credentials are rotated by the server on resume.
  String _resumeKey(Uri uri, String user) => '${_key(uri, user)}.resume';

  Future<void> _forgetResume(String user, {Uri? endpoint}) async {
    try {
      final uri = endpoint ?? await api.endpoint();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resumeKey(uri, user));
    } catch (e) {
      debugPrint('[RDesk] wake helper resume intent not cleared: $e');
    }
  }

  /// Restarts a helper the user left enabled, only on the same LAN and only
  /// with the helper identity it had; a removed helper is never recreated.
  Future<void> _resumeHelper(int gen) async {
    final user = _userId;
    if (user == null || helper.enabled) return;
    try {
      final endpoint = await api.endpoint();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_resumeKey(endpoint, user));
      if (raw == null || !_current(gen)) return;
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic> || saved['agent_id'] is! String) {
        await prefs.remove(_resumeKey(endpoint, user));
        return;
      }
      if (!await agent.selectResumeNetwork(saved)) {
        if (_current(gen)) {
          error = '上次选择的家庭网络当前不可用，开机助手没有自动恢复';
          _notify();
        }
        return;
      }
      if (!_current(gen)) return;
      await enableHelper(saved['name'] as String? ?? '家中 Mac',
          resumeAgentId: saved['agent_id'] as String);
    } catch (e) {
      if (_current(gen)) {
        error = '开机助手没有自动恢复，请重新启用';
        _notify();
      }
    }
  }

  Future<void> bindAccount(String? userId, String server,
      {String? token}) async {
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
    localWakePending = false;
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
      if (userId != null) unawaited(_resumeHelper(gen));
      if (userId != null) unawaited(_loadPending());
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
    final user = _userId;
    ++_generation;
    _userId = null;
    _timer?.cancel();
    targets = [];
    agents = [];
    history = {};
    busy = false;
    helper = const WakeAgentStatus();
    localWakePending = false;
    _notify();
    await windows?.stop();
    await agent.stop();
    await _native(agent.stop);
    // Account exit must never wait on storage or endpoint lookups.
    if (user != null) unawaited(_forgetResume(user));
  }

  void setVisible(bool visible) {
    _visible = visible;
    _timer?.cancel();
    if (visible && _foreground) {
      unawaited(refresh());
    } else {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _timer?.cancel();
    if (foreground) unawaited(refresh());
  }

  void _schedule() {
    _timer?.cancel();
    final active = targets.any(isWaking);
    if (_foreground && (_visible || active) && loggedIn && !_disposed) {
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
      if (!_current(gen)) return;
      targets = newTargets;
      final targetIds = newTargets.map((t) => t.id).toSet();
      history.removeWhere((id, _) => !targetIds.contains(id));
      error = null;
      _notify();
      Object? refreshError;
      try {
        final newAgents = await scoped.agents();
        if (!_current(gen)) return;
        agents = newAgents;
      } catch (e) {
        refreshError = e;
      }
      for (final target in newTargets) {
        if (!_current(gen)) return;
        try {
          final newHistory = await scoped.history(target.id);
          if (!_current(gen)) return;
          history[target.id] = newHistory;
        } catch (e) {
          refreshError ??= e;
        }
      }
      try {
        final status = await agent.status();
        if (!_current(gen)) return;
        helper = status;
      } catch (e) {
        refreshError ??= e;
      }
      if (!_current(gen)) return;
      error = refreshError == null ? null : _message(refreshError);
    } catch (e) {
      if (_current(gen)) error = _message(e);
    } finally {
      scoped?.close();
      _refreshing = false;
      _schedule();
      _notify();
    }
    if (_current(gen)) unawaited(_completePendingLocalWake(gen));
  }

  /// Enabled helpers, online first, then most recently seen.
  List<WakeAgent> get usableHelpers => agents.where((a) => a.enabled).toList()
    ..sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return (b.lastSeenMs ?? 0).compareTo(a.lastSeenMs ?? 0);
    });

  WakeAgent? get bestHelper => usableHelpers.firstOrNull;

  WakeTarget? targetForDevice(String deviceId) =>
      targets.where((t) => t.deviceId == deviceId).firstOrNull;

  Iterable<WakeTarget> _groupForTarget(WakeTarget target) {
    final key = wakeTargetGroupKey(target);
    return targets.where((t) => wakeTargetGroupKey(t) == key);
  }

  WakeRequest? latestRequestForTarget(WakeTarget target) {
    final ids = {target.id, ..._groupForTarget(target).map((t) => t.id)};
    WakeRequest? latest;
    for (final id in ids) {
      for (final request in history[id] ?? const <WakeRequest>[]) {
        if (latest == null || request.createdAtMs > latest.createdAtMs) {
          latest = request;
        }
      }
    }
    return latest;
  }

  bool isWaking(WakeTarget target) {
    final members = _groupForTarget(target).toList();
    if (target.online || members.any((t) => t.online)) return false;
    final ids = {target.id, ...members.map((t) => t.id)};
    return ids.any((id) => history[id]?.any((r) => r.active) ?? false);
  }

  String _pendingKey(Uri uri, String user) => '${_key(uri, user)}.windows';

  /// True while this Windows PC waits for a home helper before enrolling.
  bool localWakePending = false;

  Future<void> _loadPending() async {
    final user = _userId;
    if (windows == null || user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey(await api.endpoint(), user));
      final pending = raw != null;
      if (pending != localWakePending && _userId == user) {
        localWakePending = pending;
        _notify();
      }
    } catch (e) {
      debugPrint('[RDesk] wake pending state unavailable: $e');
    }
  }

  Future<void> _completePendingLocalWake(int gen) async {
    final user = _userId;
    if (windows == null || user == null || busy) return;
    try {
      final endpoint = await api.endpoint();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey(endpoint, user));
      if (raw == null || !_current(gen)) {
        if (localWakePending && _current(gen)) {
          localWakePending = false;
          _notify();
        }
        return;
      }
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final helper = bestHelper;
      if (helper == null) {
        if (!localWakePending) {
          localWakePending = true;
          _notify();
        }
        return;
      }
      final ok = await _mutate((_, g) async {
        await windows!.enroll(
            userId: user,
            deviceId: saved['device_id'] as String,
            name: saved['name'] as String,
            mac: saved['mac'] as String,
            agentId: helper.id);
        await prefs.remove(_pendingKey(endpoint, user));
        if (_current(g)) localWakePending = false;
      });
      if (ok && _current(gen)) await refresh();
    } catch (e) {
      debugPrint('[RDesk] pending remote wake not completed: $e');
    }
  }

  /// Windows: allow this PC to be woken. Picks a home helper automatically;
  /// without one the choice is remembered and completed once a helper appears.
  Future<bool> enableLocalWake(
          {required String deviceId,
          required String name,
          required String mac}) =>
      _mutate((scoped, gen) async {
        if (windows == null) throw StateError('请在要开机的 Windows 电脑上开启');
        final user = _userId!;
        final endpoint = await scoped.endpoint();
        final latest = await scoped.agents();
        if (!_current(gen)) return;
        agents = latest;
        final helper = bestHelper;
        final prefs = await SharedPreferences.getInstance();
        if (helper == null) {
          await prefs.setString(_pendingKey(endpoint, user),
              jsonEncode({'device_id': deviceId, 'name': name, 'mac': mac}));
          localWakePending = true;
          return;
        }
        await windows!.enroll(
            userId: user,
            deviceId: deviceId,
            name: name,
            mac: mac,
            agentId: helper.id);
        await prefs.remove(_pendingKey(endpoint, user));
        localWakePending = false;
        if (_current(gen)) await refresh();
      });

  /// Windows: stop accepting remote wake for this PC.
  Future<bool> disableLocalWake(String deviceId) =>
      _mutate((scoped, gen) async {
        final user = _userId!;
        final endpoint = await scoped.endpoint();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingKey(endpoint, user));
        localWakePending = false;
        final target = targetForDevice(deviceId);
        if (target != null) await scoped.deleteTarget(target.id);
        await windows?.forget(user);
        if (_current(gen)) await refresh();
      });

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

  Future<bool> enableHelper(String name, {String? resumeAgentId}) =>
      _mutate((scoped, gen) async {
        final user = _userId!;
        await agent.prepare();
        if (!_current(gen)) return;
        final endpoint = await scoped.endpoint();
        final prefs = await SharedPreferences.getInstance();
        if (!_current(gen)) return;
        final key = _key(endpoint, user);
        final oldId = prefs.getString(key);
        if (resumeAgentId != null && oldId != resumeAgentId) {
          await prefs.remove(_resumeKey(endpoint, user));
          throw StateError('开机助手已更换，请重新启用');
        }
        await _native(agent.stop);
        if (!_current(gen)) return;
        WakeEnrollment? enrollment;
        bool created = false;
        if (oldId != null) {
          try {
            enrollment = await scoped.enableAgent(oldId, name);
          } on WakeApiException catch (e) {
            if (e.statusCode != 404) rethrow;
            if (resumeAgentId != null) {
              await prefs.remove(_resumeKey(endpoint, user));
              throw StateError('开机助手已在其他设备移除，请重新启用');
            }
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
          final network = agent.resumeNetwork;
          if (_current(gen) && network != null) {
            await prefs.setString(
                _resumeKey(endpoint, user),
                jsonEncode(
                    {'agent_id': registered.id, 'name': name, ...network}));
          }
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
        await _forgetResume(user, endpoint: endpoint);
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
        // Page snapshots may predate a helper restart or another device's edit.
        final latestTargets = await scoped.targets();
        if (!_current(gen)) return;
        targets = latestTargets;
        final latest =
            latestTargets.where((t) => t.id == target.id).firstOrNull;
        if (latest == null) throw StateError('这台电脑的远程开机设置已移除，请刷新设备列表');
        if (latest.online) throw StateError('电脑已经在线');
        final latestHistory = await scoped.history(latest.id);
        if (!_current(gen)) return;
        history[latest.id] = latestHistory;
        if (latestHistory.any((r) => r.active)) {
          throw StateError('正在开机，请稍候');
        }
        final latestAgents = await scoped.agents();
        if (!_current(gen)) return;
        agents = latestAgents;
        final boundHelper = agents
            .where((a) => a.id == latest.agentId && a.enabled && a.online)
            .firstOrNull;
        if (boundHelper == null) {
          // The bound helper is away: use a currently online helper instead.
          final alternative =
              agents.where((a) => a.enabled && a.online).firstOrNull;
          if (alternative == null) {
            throw StateError('家中没有在线的开机助手。请在家里的安卓手机或 Mac 上打开随控并开启开机助手。');
          }
          await scoped.updateTarget(latest.id,
              name: latest.name, mac: latest.mac, agentId: alternative.id);
          if (!_current(gen)) return;
        }
        final request = await scoped.requestWake(latest.id);
        if (_current(gen)) {
          history[latest.id] = [
            request,
            ...?history[latest.id]?.where((r) => r.id != request.id)
          ];
          _schedule();
        }
      });
  Future<bool> completeTarget(String id, String agentId) =>
      _mutate((scoped, gen) async {
        await scoped.completeTarget(id, agentId);
        if (_current(gen)) await refresh();
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
        if (helper.agentId == selected.id) {
          await _forgetResume(_userId!, endpoint: await scoped.endpoint());
          await _native(agent.stop);
        }
        await scoped.revokeAgent(selected.id);
        if (_current(gen)) await refresh();
      });
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    ++_generation;
    _timer?.cancel();
    unawaited(windows?.dispose() ?? Future.value());
    api.close();
    super.dispose();
  }
}
