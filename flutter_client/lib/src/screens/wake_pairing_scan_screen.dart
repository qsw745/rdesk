import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/wake_pairing.dart';
import '../providers/wake_provider.dart';
import '../services/wake_api.dart';
import '../services/pairing_scan_camera.dart';
import 'wake_pairing_confirm_screen.dart';

class WakePairingScanScreen extends StatefulWidget {
  final PairingScanCamera? camera;
  const WakePairingScanScreen({super.key, this.camera});
  @override
  State<WakePairingScanScreen> createState() => _WakePairingScanScreenState();
}

class _WakePairingScanScreenState extends State<WakePairingScanScreen>
    with WidgetsBindingObserver {
  late final PairingScanCamera _camera =
      widget.camera ?? MobilePairingScanCamera();
  final _manual = TextEditingController();
  bool _started = false,
      _starting = false,
      _busy = false,
      _foreground = true,
      _covered = false;
  int _generation = 0;
  int? _identity;
  String? _error;
  WakeApi? _request;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = context.watch<WakeProvider>().identityGeneration;
    if (_identity != null && _identity != identity) {
      ++_generation;
      _started = false;
      _busy = false;
      _request?.close();
      unawaited(_camera.stop());
      _error = '账号或服务器已变更，请重新扫码';
    }
    _identity = identity;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      ++_generation;
      unawaited(_camera.stop());
    } else if (_started && !_covered && !_busy && _camera.canResume) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    if (_starting || _busy || !_foreground) return;
    final gen = _generation;
    setState(() {
      _starting = true;
      _started = true;
      _error = null;
    });
    try {
      await _camera.start();
      if (!mounted || gen != _generation || !_foreground || _covered) {
        await _camera.stop();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法使用相机，请允许相机权限，或输入电脑上的配对码');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _scan(String value) async {
    if (_busy || !_foreground || _covered) return;
    WakePairingCode code;
    try {
      code = WakePairingCode.parse(value);
    } on FormatException catch (e) {
      await _camera.stop();
      if (mounted) setState(() => _error = e.message);
      return;
    }
    await _resolve(code);
  }

  Future<void> _resolve(WakePairingCode code) async {
    if (_busy) return;
    final wake = context.read<WakeProvider>();
    if (!wake.loggedIn) return;
    final account = wake.identityGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _camera.stop();
    try {
      final api = await wake.api.scoped();
      _request = api;
      if (!mounted || !wake.loggedIn || account != wake.identityGeneration) {
        return;
      }
      final summary = await api.resolvePairing(code);
      if (!mounted || !wake.loggedIn || account != wake.identityGeneration) {
        return;
      }
      _covered = true;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => WakePairingConfirmScreen(
              code: code, summary: summary, accountGeneration: account)));
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = e is WakeApiException ? e.message : '无法读取配对信息，请重试');
      }
    } finally {
      _request?.close();
      _request = null;
      _covered = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _request?.close();
    unawaited(_camera.dispose());
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('扫码添加电脑')),
        body: !wake.loggedIn
            ? Center(
                child: FilledButton(
                    onPressed: () => context.push('/login?redirect=/wake/scan'),
                    child: const Text('登录后扫码')))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                  '在 Windows 电脑上打开 RDesk → 远程开机，生成配对二维码。手机和电脑需登录同一账号。'),
                              const SizedBox(height: 20),
                              AspectRatio(
                                  aspectRatio: 1.25,
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: _camera.preview(_scan))),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: _busy || _starting ? null : _start,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: Text(_starting
                                      ? '正在开启相机…'
                                      : _started
                                          ? '重新扫描'
                                          : '开启相机扫码')),
                              if (_busy)
                                const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator()),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              const SizedBox(height: 24),
                              TextField(
                                  controller: _manual,
                                  maxLength: 19,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                      labelText: '无法扫码？输入 16 位配对码',
                                      hintText: '例如 ABCD EFGH JKLM NPQR',
                                      counterText: '')),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          final code = _manual.text
                                              .replaceAll(RegExp(r'[\s-]'), '')
                                              .toUpperCase();
                                          if (!RegExp(
                                                  r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{16}$')
                                              .hasMatch(code)) {
                                            setState(() =>
                                                _error = '请输入电脑上显示的 16 位配对码');
                                            return;
                                          }
                                          unawaited(_resolve(
                                              WakePairingCode.manual(code)));
                                        },
                                  child: const Text('使用配对码继续')),
                            ])))));
  }
}
