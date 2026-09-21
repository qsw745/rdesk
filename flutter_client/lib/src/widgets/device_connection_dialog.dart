import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_directory_entry.dart';
import '../models/session.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/device_directory.dart';
import '../utils/device_address.dart';

class DeviceConnectionResult {
  final String sessionId, password;
  const DeviceConnectionResult(this.sessionId, this.password);
}

/// Account membership is a UI hint; the server authorizes every connection.
class DeviceConnectionDialog extends StatefulWidget {
  final DeviceDirectoryEntry device;
  const DeviceConnectionDialog({super.key, required this.device});
  @override
  State<DeviceConnectionDialog> createState() => _DeviceConnectionDialogState();
}

class _DeviceConnectionDialogState extends State<DeviceConnectionDialog> {
  final _password = TextEditingController();
  late final ConnectionProvider _connection;
  late final AuthProvider _auth;
  late final SettingsProvider _settings;
  String? _scope, _token, _error;
  bool _busy = true, _sourceConfirmed = false, _cancelled = false;
  bool get _identityCurrent =>
      _auth.session?.token == _token &&
      normalizedEndpointScope(_settings.signalingServer) == _scope;

  @override
  void initState() {
    super.initState();
    _connection = context.read<ConnectionProvider>();
    _auth = context.read<AuthProvider>();
    _settings = context.read<SettingsProvider>();
    _token = _auth.session?.token;
    _scope = normalizedEndpointScope(_settings.signalingServer);
    _sourceConfirmed = widget.device.endpointScope != null;
    _auth.addListener(_identityChanged);
    _settings.addListener(_identityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  void _identityChanged() {
    if (_identityCurrent || !mounted || _cancelled) return;
    _cancelled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _prepare() async {
    if (!mounted || _cancelled) return;
    try {
      if (widget.device.accountOwned &&
          _token != null &&
          _sourceConfirmed &&
          !isDirectDeviceAddress(widget.device.deviceId)) {
        await _connect();
        return;
      }
      // Existing trusted-peer passwords have no server scope. Never send them
      // automatically to a directory entry; ask for credentials on this route.
      setState(() => _busy = false);
    } catch (_) {
      if (mounted && !_cancelled) {
        setState(() {
          _busy = false;
          _error = '无法读取连接信息，请重试。';
        });
      }
    }
  }

  Future<void> _connect() async {
    if (!mounted || _cancelled || !_identityCurrent) return;
    if (_connection.connectionState == SessionState.connecting) {
      setState(() {
        _busy = false;
        _error = '另一个连接仍在处理中，请稍后重试。';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final password = _password.text;
    String? id;
    try {
      id = isDirectDeviceAddress(widget.device.deviceId)
          ? await _connection.connectDirectIp(widget.device.deviceId,
              password: password)
          : await _connection.connect(widget.device.deviceId, password);
      if (!mounted || _cancelled || !_identityCurrent) {
        if (id != null) await _connection.disconnect(id);
        return;
      }
      if (id != null) {
        Navigator.of(context).pop(DeviceConnectionResult(id, password));
      } else {
        setState(() {
          _busy = false;
          _error = _connection.errorMessage ?? '连接失败，请确认对方已开启共享。';
        });
      }
    } catch (_) {
      if (id != null) await _connection.disconnect(id);
      if (mounted && !_cancelled) {
        setState(() {
          _busy = false;
          _error = '连接失败，请检查网络后重试。';
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _auth.removeListener(_identityChanged);
    _settings.removeListener(_identityChanged);
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            _busy ? '正在连接 ${widget.device.name}' : '连接 ${widget.device.name}'),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(widget.device.accountOwned
                      ? '正在验证同账号设备…'
                      : '正在连接，请等待对方确认…'),
                ] else ...[
                  if (isDirectDeviceAddress(widget.device.deviceId)) ...[
                    Text('直接连接 ${widget.device.deviceId}，请确认这是你的设备地址。'),
                    const SizedBox(height: 16),
                  ] else if (!_sourceConfirmed) ...[
                    const Text('这条旧记录未保存服务器。确认使用当前服务器查找此设备后再连接。'),
                    const SizedBox(height: 8),
                    Text(_scope ?? '服务器未设置'),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                          labelText: '访问密码（可选）', hintText: '留空则请求对方确认'),
                      onSubmitted: (_) => _connect()),
                  const SizedBox(height: 12),
                  const Text('对方需要开启设备共享。同账号设备由服务器验证，无需重复输入密码。'),
                ],
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () {
                _cancelled = true;
                Navigator.of(context).pop();
              },
              child: const Text('取消')),
          if (!_busy)
            FilledButton(
                onPressed: _connect,
                child: Text(_sourceConfirmed ? '连接' : '确认并连接')),
        ],
      );
}
