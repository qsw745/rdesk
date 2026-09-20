import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wake_pairing.dart';
import '../providers/wake_provider.dart';
import '../services/wake_api.dart';
import 'wake_mobile_setup_screen.dart';

class WakePairingConfirmScreen extends StatefulWidget {
  final WakePairingCode code;
  final Map<String, dynamic> summary;
  final int accountGeneration;
  const WakePairingConfirmScreen(
      {super.key,
      required this.code,
      required this.summary,
      required this.accountGeneration});
  @override
  State<WakePairingConfirmScreen> createState() =>
      _WakePairingConfirmScreenState();
}

class _WakePairingConfirmScreenState extends State<WakePairingConfirmScreen>
    with WidgetsBindingObserver {
  bool _busy = false,
      _waiting = false,
      _foreground = true,
      _polling = false,
      _done = false;
  String? _error;
  Timer? _timer;
  WakeApi? _api;
  Set<String> _previous = {};
  bool get _current =>
      mounted &&
      context.read<WakeProvider>().loggedIn &&
      context.read<WakeProvider>().identityGeneration ==
          widget.accountGeneration;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && _waiting) unawaited(_poll());
  }

  Future<void> _confirm() async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _api ??= await context.read<WakeProvider>().api.scoped();
      _previous = (await _api!.targets()).map((t) => t.id).toSet();
      if (!mounted || !_current) return;
      try {
        await _api!.confirmPairing(widget.summary['id'] as String, widget.code);
      } on WakeApiException catch (e) {
        if (e.statusCode != 409 && e.code != 'network' && e.code != 'timeout') {
          rethrow;
        }
        // A lost response or another scan may have already confirmed this pairing.
        final summary = await _api!.resolvePairing(widget.code);
        if (summary['state'] != 'confirmed' && summary['state'] != 'claimed') {
          rethrow;
        }
      }
      if (!mounted || !_current) return;
      setState(() => _waiting = true);
      await _poll();
    } catch (e) {
      if (_current) {
        setState(
            () => _error = e is WakeApiException ? e.message : '配对暂未完成，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (!_current || !_waiting || _polling || _done || !_foreground) return;
    _polling = true;
    try {
      String? id;
      try {
        final summary = await _api!.resolvePairing(widget.code);
        if (summary['state'] == 'claimed') id = summary['target_id'] as String?;
      } on WakeApiException catch (e) {
        if (e.statusCode != 404 && e.statusCode != 410) rethrow;
      }
      if (!mounted || !_current) return;
      if (id == null) {
        final targets = await _api!.targets();
        id = targets
            .where((t) =>
                t.deviceId == widget.summary['device_id'] &&
                !_previous.contains(t.id))
            .firstOrNull
            ?.id;
      }
      if (!mounted || !_current) return;
      if (id != null) {
        _done = true;
        _timer?.cancel();
        await context.read<WakeProvider>().refresh();
        if (!mounted || !_current) return;
        unawaited(Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => WakeMobileSetupScreen(targetId: id!))));
        return;
      }
      if (DateTime.now().millisecondsSinceEpoch >=
          (widget.summary['expires_at_ms'] as num).toInt()) {
        _waiting = false;
        setState(() => _error = '配对码已过期。请返回设备列表检查是否已添加，或在电脑重新生成。');
      }
    } catch (e) {
      if (_current) {
        setState(() => _error =
            e is WakeApiException ? e.message : '正在等待电脑，请保持两端 RDesk 打开');
      }
    } finally {
      _polling = false;
      if (_current && _waiting && !_done && _foreground) {
        _timer = Timer(const Duration(seconds: 2), () => unawaited(_poll()));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WakeProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('确认添加电脑')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Icon(Icons.desktop_windows_outlined, size: 72),
                      const SizedBox(height: 24),
                      Text(widget.summary['name'] as String,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      const Text('确认这是你要添加的电脑。添加后还需完成家中助手和 BIOS 设置。',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      if (!_current)
                        const Text('账号或服务器已变更，请返回重新扫码。')
                      else if (_waiting) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('手机已确认，正在等待电脑领取配对。\n请保持电脑上的 RDesk 打开。',
                            textAlign: TextAlign.center)
                      ] else
                        FilledButton(
                            onPressed: _busy ? null : _confirm,
                            child: Text(_busy ? '正在确认…' : '确认添加这台电脑')),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))
                    ]))));
  }
}
