import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/connection_info.dart';
import '../models/session.dart';
import '../providers/android_host_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/desktop_host_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';
import '../widgets/device_id_display.dart';

enum _ConnectMode { remoteControl, fileTransfer }

class RemoteAssistScreen extends StatefulWidget {
  const RemoteAssistScreen({super.key});

  @override
  State<RemoteAssistScreen> createState() => _RemoteAssistScreenState();
}

class _RemoteAssistScreenState extends State<RemoteAssistScreen> {
  final _deviceIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceIdFocusNode = FocusNode();
  bool _showPassword = false;
  bool _didApplyPendingQuickConnect = false;
  _ConnectMode _connectMode = _ConnectMode.remoteControl;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _passwordController.dispose();
    _deviceIdFocusNode.dispose();
    super.dispose();
  }

  Future<void> _applyQuickConnectPeer(String peerId) async {
    final connectionProvider = context.read<ConnectionProvider>();
    _deviceIdController.text = peerId;
    if (_passwordController.text.trim().isEmpty) {
      final cachedPassword =
          await connectionProvider.getTrustedPassword(peerId);
      if (cachedPassword != null && cachedPassword.isNotEmpty) {
        _passwordController.text = cachedPassword;
      }
    }
    if (mounted) setState(() {});
  }

  /// Returns true if [input] looks like an IP address (with optional :port).
  bool _looksLikeIpAddress(String input) {
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$');
    return ipPattern.hasMatch(input);
  }

  Future<void> _connect({bool passwordless = false}) async {
    final input = _deviceIdController.text.trim();
    final password = passwordless ? '' : _passwordController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入设备ID或IP地址')),
      );
      return;
    }

    if (_looksLikeIpAddress(input)) {
      await _connectDirectIp(input, password: password);
    } else {
      await _connectToPeer(input, password);
    }
  }

  Future<void> _connectDirectIp(String address, {String? password}) async {
    final provider = context.read<ConnectionProvider>();
    final sessionProvider = context.read<SessionProvider>();

    final sessionId =
        await provider.connectDirectIp(address, password: password);
    if (!mounted || sessionId == null) {
      if (mounted) {
        final errorMsg = provider.errorMessage ?? '连接失败';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    sessionProvider.setSession(
      SessionInfo(
        sessionId: sessionId,
        peerId: address,
        peerHostname: '直连 $address',
        peerOs: 'direct-lan',
        state: SessionState.active,
        connectedAt: DateTime.now(),
      ),
    );

    if (_connectMode == _ConnectMode.fileTransfer) {
      context.go('/files/$sessionId');
    } else {
      context.go('/remote/$sessionId');
    }
  }

  Future<void> _connectToPeer(String deviceId, String password) async {
    final provider = context.read<ConnectionProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final sessionId = await provider.connect(deviceId, password);
    if (!mounted || sessionId == null) return;
    await settingsProvider.refreshTrustedPeers();
    if (!mounted) return;

    sessionProvider.setSession(
      SessionInfo(
        sessionId: sessionId,
        peerId: deviceId,
        peerHostname: '远程设备 $deviceId',
        peerOs: '未知系统',
        state: SessionState.active,
        connectedAt: DateTime.now(),
      ),
      accessPassword: password,
    );

    if (_connectMode == _ConnectMode.fileTransfer) {
      context.go('/files/$sessionId');
    } else {
      context.go('/remote/$sessionId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didApplyPendingQuickConnect) {
      _didApplyPendingQuickConnect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final peerId =
            context.read<ConnectionProvider>().consumeQuickConnectPeerId();
        if (peerId != null && peerId.isNotEmpty) {
          _applyQuickConnectPeer(peerId);
        }
      });
    }

    final records = context.watch<ConnectionProvider>().recentConnections;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('远程连接'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // --- Connect remote device card ---
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.connected_tv_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '连接远程设备',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '输入设备代码发起连接',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Device ID input with autocomplete
                      RawAutocomplete<ConnectionRecord>(
                        textEditingController: _deviceIdController,
                        focusNode: _deviceIdFocusNode,
                        optionsBuilder: (value) {
                          final keyword = value.text.trim();
                          return records.where((record) {
                            if (keyword.isEmpty) return true;
                            return record.peerId.contains(keyword) ||
                                record.peerHostname
                                    .toLowerCase()
                                    .contains(keyword.toLowerCase());
                          });
                        },
                        displayStringForOption: (option) => option.peerId,
                        onSelected: (option) {
                          _applyQuickConnectPeer(option.peerId);
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          final items = options.toList();
                          if (items.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(14),
                              color: cardBg,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 220),
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width - 80,
                                  child: ListView.separated(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    shrinkWrap: true,
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(
                                            Icons.devices_rounded,
                                            size: 18,
                                            color: AppTheme.primaryBlue),
                                        title: Text(item.peerId,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        subtitle: Text(item.peerHostname,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        onTap: () => onSelected(item),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              prefixIcon:
                                  const Icon(Icons.tag_rounded, size: 20),
                              hintText: '设备代码 或 IP:端口',
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded,
                                          size: 18),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() {});
                                      },
                                    )
                                  : const Icon(Icons.arrow_drop_down_rounded),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF5F7FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppTheme.primaryBlue, width: 1.5),
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.:]')),
                              LengthLimitingTextInputFormatter(21),
                            ],
                            onChanged: (_) => setState(() {}),
                            onTap: () {
                              if (controller.text.isEmpty) {
                                focusNode.requestFocus();
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Password input
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.lock_outline_rounded, size: 20),
                          hintText: '请输入验证码',
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppTheme.primaryBlue, width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Mode selector: remote control / file transfer
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF0F3F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _ModeTab(
                              label: '远程控制',
                              icon: Icons.desktop_windows_rounded,
                              selected:
                                  _connectMode == _ConnectMode.remoteControl,
                              isDark: isDark,
                              onTap: () => setState(() =>
                                  _connectMode = _ConnectMode.remoteControl),
                            ),
                            _ModeTab(
                              label: '文件传输',
                              icon: Icons.folder_open_rounded,
                              selected:
                                  _connectMode == _ConnectMode.fileTransfer,
                              isDark: isDark,
                              onTap: () => setState(() =>
                                  _connectMode = _ConnectMode.fileTransfer),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Dual action buttons
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          final isConnecting = provider.connectionState ==
                              SessionState.connecting;
                          return Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: isConnecting
                                        ? null
                                        : () => _connect(passwordless: true),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: AppTheme.primaryBlue),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('免密连接',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: isConnecting
                                          ? null
                                          : AppTheme.brandGradient,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: isConnecting
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: AppTheme.primaryBlue
                                                    .withValues(alpha: 0.2),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: isConnecting ? null : _connect,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        disabledBackgroundColor: isDark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade300,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: isConnecting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('密码连接',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              )),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      // Error display
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          final error = provider.errorMessage;
                          if (error == null || error.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.errorRed.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppTheme.errorRed, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(error,
                                        style: const TextStyle(
                                            color: AppTheme.errorRed,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Recent connections (circular avatar row) ---
          Consumer<ConnectionProvider>(
            builder: (context, provider, _) {
              final recentRecords = provider.recentConnections.take(8).toList();
              if (recentRecords.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      '最近连接',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recentRecords.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final record = recentRecords[index];
                        return _RecentAvatarItem(
                          record: record,
                          isDark: isDark,
                          onTap: () => _applyQuickConnectPeer(record.peerId),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // --- Desktop host status + direct connect address ---
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            Consumer<DesktopHostProvider>(
              builder: (context, host, _) {
                final endpoint = host.lanRelayEndpoint;
                final isRunning = host.state.isRunning;
                if (!isRunning || endpoint == null || endpoint.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lan_outlined,
                          size: 18, color: Colors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '本机直连地址（局域网 / Tailscale）',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              endpoint,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '其他设备输入此地址可局域网直连，延迟更低',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: endpoint));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('直连地址已复制'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: '复制',
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            const SizedBox(height: 20),

          // --- "Connect to this device" section ---
          Consumer<ConnectionProvider>(
            builder: (context, connection, _) {
              final localDevice = connection.localDevice;
              final bool isDesktop =
                  Platform.isMacOS || Platform.isWindows || Platform.isLinux;
              final lanEndpoint = isDesktop
                  ? context.watch<DesktopHostProvider>().lanRelayEndpoint
                  : Platform.isAndroid
                      ? context.watch<AndroidHostProvider>().lanRelayEndpoint
                      : null;
              return DeviceIdDisplay(
                compact: true,
                deviceId: localDevice?.deviceId ?? '000000000',
                temporaryPassword: connection.temporaryPassword,
                onRefreshPassword: connection.refreshPassword,
                lanEndpoint: lanEndpoint,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF2A3050) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.primaryBlue : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentAvatarItem extends StatelessWidget {
  final ConnectionRecord record;
  final bool isDark;
  final VoidCallback onTap;

  const _RecentAvatarItem({
    required this.record,
    required this.isDark,
    required this.onTap,
  });

  static const _gradients = [
    [Color(0xFF6CB6FF), Color(0xFF2258D6)],
    [Color(0xFF62C870), Color(0xFF0B8B65)],
    [Color(0xFFB9A0FF), Color(0xFF7C5CE0)],
    [Color(0xFFFF9F6C), Color(0xFFE05B2A)],
    [Color(0xFF68D5E8), Color(0xFF2E9BB0)],
  ];

  @override
  Widget build(BuildContext context) {
    final initial = record.peerHostname.isNotEmpty
        ? record.peerHostname.substring(0, 1).toUpperCase()
        : '?';
    final hashIndex = record.peerId.hashCode.abs() % _gradients.length;
    final colors = _gradients[hashIndex];

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors[0].withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              record.peerHostname,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white60 : AppTheme.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
