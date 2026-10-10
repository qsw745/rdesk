import 'dart:async';
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
import '../ui/components.dart';
import '../ui/tokens.dart';
import '../utils/platform_capabilities.dart';

/// Remote assistance: control someone else's device, or let them control this one.
class RemoteAssistScreen extends StatefulWidget {
  const RemoteAssistScreen({super.key});

  @override
  State<RemoteAssistScreen> createState() => _RemoteAssistScreenState();
}

class _RemoteAssistScreenState extends State<RemoteAssistScreen> {
  final _deviceId = TextEditingController();
  final _password = TextEditingController();
  final _deviceIdFocus = FocusNode();
  bool _showPassword = false, _appliedQuickConnect = false, _busy = false;

  @override
  void dispose() {
    _deviceId.dispose();
    _password.dispose();
    _deviceIdFocus.dispose();
    super.dispose();
  }

  Future<void> _prefill(String peerId) async {
    final connection = context.read<ConnectionProvider>();
    _deviceId.text = formatDeviceId(peerId);
    if (_password.text.trim().isEmpty) {
      final cached = await connection.getTrustedPassword(peerId);
      if (cached != null && cached.isNotEmpty) _password.text = cached;
    }
    if (mounted) setState(() {});
  }

  static bool _looksLikeIp(String input) =>
      RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$').hasMatch(input);

  /// An empty verification code asks the other side to accept the request.
  Future<void> _connect({required bool files}) async {
    final input = _deviceId.text.replaceAll(' ', '').trim();
    final password = _password.text.trim();
    if (input.isEmpty) {
      _deviceIdFocus.requestFocus();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入对方的设备码')));
      return;
    }
    final provider = context.read<ConnectionProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final direct = _looksLikeIp(input);
      final sessionId = direct
          ? await provider.connectDirectIp(input, password: password)
          : await provider.connect(input, password);
      if (!mounted) return;
      if (sessionId == null) {
        if (direct) {
          messenger.showSnackBar(
              SnackBar(content: Text(provider.errorMessage ?? '连接失败')));
        }
        return;
      }
      if (!direct) await settings.refreshTrustedPeers();
      if (!mounted) return;
      sessionProvider.setSession(
        SessionInfo(
          sessionId: sessionId,
          peerId: input,
          peerHostname: direct ? '直连 $input' : '远程设备 ${formatDeviceId(input)}',
          peerOs: provider.peerPlatformForSession(sessionId) ?? '未知系统',
          state: SessionState.active,
          connectedAt: DateTime.now(),
        ),
        accessPassword: direct ? null : password,
      );
      context.go(files ? '/files/$sessionId' : '/remote/$sessionId');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_appliedQuickConnect) {
      _appliedQuickConnect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final peerId =
            context.read<ConnectionProvider>().consumeQuickConnectPeerId();
        if (peerId != null && peerId.isNotEmpty) unawaited(_prefill(peerId));
      });
    }
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final connectCard = _ConnectCard(
      deviceId: _deviceId,
      password: _password,
      focus: _deviceIdFocus,
      showPassword: _showPassword,
      busy: _busy ||
          context.watch<ConnectionProvider>().connectionState ==
              SessionState.connecting,
      onTogglePassword: () => setState(() => _showPassword = !_showPassword),
      onPick: _prefill,
      onConnect: _connect,
    );
    final hostCard = PlatformCapabilities.current.canHost
        ? const _ThisDeviceCard()
        : const _HostUnsupportedCard();
    final recent = _RecentConnections(onPick: _prefill);

    return RdPage(
      title: '远程协助',
      subtitle: '控制他人的设备，或让他人远程帮你操作',
      maxWidth: 1080,
      children: wide
          ? [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: connectCard),
                const SizedBox(width: 20),
                Expanded(child: hostCard),
              ]),
              const SizedBox(height: 28),
              recent,
            ]
          : [
              connectCard,
              const SizedBox(height: 16),
              hostCard,
              const SizedBox(height: 28),
              recent,
            ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final RdTone tone;
  final Widget? trailing;
  const _CardTitle(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.tone = RdTone.brand,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      RdIconBadge(icon: icon, tone: tone, size: 40),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.titleMedium),
        const SizedBox(height: 2),
        Text(subtitle, style: t.bodySmall),
      ])),
      if (trailing != null) trailing!,
    ]);
  }
}

class _ConnectCard extends StatelessWidget {
  final TextEditingController deviceId, password;
  final FocusNode focus;
  final bool showPassword, busy;
  final VoidCallback onTogglePassword;
  final ValueChanged<String> onPick;
  final Future<void> Function({required bool files}) onConnect;
  const _ConnectCard(
      {required this.deviceId,
      required this.password,
      required this.focus,
      required this.showPassword,
      required this.busy,
      required this.onTogglePassword,
      required this.onPick,
      required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final records = context.watch<ConnectionProvider>().recentConnections;
    return RdCard(
      padding: const EdgeInsets.all(20),
      radius: Rd.radiusLg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _CardTitle(
            icon: Icons.screen_share_rounded,
            title: '远程控制其他设备',
            subtitle: '输入对方随控上显示的设备码'),
        const SizedBox(height: 20),
        RawAutocomplete<ConnectionRecord>(
          textEditingController: deviceId,
          focusNode: focus,
          optionsBuilder: (value) {
            final keyword = value.text.replaceAll(' ', '').trim().toLowerCase();
            final seen = <String>{};
            return records.where((r) =>
                seen.add(r.peerId) &&
                (keyword.isEmpty ||
                    r.peerId.contains(keyword) ||
                    r.peerHostname.toLowerCase().contains(keyword)));
          },
          displayStringForOption: (r) => formatDeviceId(r.peerId),
          onSelected: (r) => onPick(r.peerId),
          fieldViewBuilder: (context, controller, node, submit) => TextField(
            controller: controller,
            focusNode: node,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(letterSpacing: 1, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              labelText: '设备码',
              hintText: '例如 123 456 789，也可输入局域网 IP',
              prefixIcon: Icon(Icons.tag_rounded, size: 20),
            ),
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(Rd.radius),
              color: RdPalette.of(context).surface,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 240, maxWidth: 420),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final r in options)
                      ListTile(
                        dense: true,
                        leading: RdDeviceGlyph(platform: r.peerOs, size: 32),
                        title: Text(r.peerHostname,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatDeviceId(r.peerId)),
                        onTap: () => onSelected(r),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: !showPassword,
          onSubmitted: (_) => onConnect(files: false),
          decoration: InputDecoration(
            labelText: '验证码（选填）',
            hintText: '不填则请求对方同意',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              onPressed: onTogglePassword,
              tooltip: showPassword ? '隐藏' : '显示',
              icon: Icon(
                  showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              onPressed: busy ? null : () => onConnect(files: false),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.desktop_windows_rounded, size: 18),
              label: Text(busy ? '正在连接' : '远程控制'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => onConnect(files: true),
              icon: const Icon(Icons.folder_copy_rounded, size: 18),
              label: const Text('传输文件'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// This device's code, temporary password and sharing switch.
class _ThisDeviceCard extends StatefulWidget {
  const _ThisDeviceCard();

  @override
  State<_ThisDeviceCard> createState() => _ThisDeviceCardState();
}

class _ThisDeviceCardState extends State<_ThisDeviceCard> {
  bool _reveal = false;

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final connection = context.watch<ConnectionProvider>();
    final desktop = PlatformCapabilities.current.hasDesktopHost;
    final DesktopHostProvider? mac =
        desktop ? context.watch<DesktopHostProvider>() : null;
    final AndroidHostProvider? mobile =
        desktop ? null : context.watch<AndroidHostProvider>();
    final running = mac?.hostingEnabled ?? mobile?.state.isRunning ?? false;
    final lan = mac?.lanRelayEndpoint ?? mobile?.lanRelayEndpoint;
    final id = connection.localDevice?.deviceId;
    final code = connection.temporaryPassword;

    Widget field(String label, Widget value, List<Widget> actions) => Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
              color: p.surfaceMuted,
              borderRadius: BorderRadius.circular(Rd.radius)),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, style: t.labelSmall),
                  const SizedBox(height: 2),
                  value,
                ])),
            ...actions,
          ]),
        );

    return RdCard(
      padding: const EdgeInsets.all(20),
      radius: Rd.radiusLg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(
          icon: Icons.phonelink_ring_rounded,
          tone: RdTone.online,
          title: '允许别人控制本设备',
          subtitle: running ? '把设备码和验证码告诉对方' : '开启共享后，对方才能连接',
          trailing: RdStatusPill(running ? '共享中' : '未开启',
              tone: running ? RdTone.online : RdTone.neutral),
        ),
        const SizedBox(height: 20),
        field(
            '本机设备码',
            Text(id == null ? '获取中…' : formatDeviceId(id),
                style: t.headlineSmall!
                    .copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            [
              if (id != null)
                IconButton(
                    tooltip: '复制设备码',
                    onPressed: () => _copy(id, '设备码'),
                    icon: const Icon(Icons.content_copy_rounded, size: 20)),
            ]),
        const SizedBox(height: 10),
        field(
            '临时验证码',
            Text(code.isEmpty ? '——' : (_reveal ? code : '••••••'),
                style: t.titleLarge!.copyWith(letterSpacing: 3)),
            [
              IconButton(
                  tooltip: _reveal ? '隐藏' : '显示',
                  onPressed: () => setState(() => _reveal = !_reveal),
                  icon: Icon(
                      _reveal
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 20)),
              IconButton(
                  tooltip: '换一个',
                  onPressed: connection.refreshPassword,
                  icon: const Icon(Icons.refresh_rounded, size: 20)),
              if (code.isNotEmpty)
                IconButton(
                    tooltip: '复制验证码',
                    onPressed: () => _copy(code, '验证码'),
                    icon: const Icon(Icons.content_copy_rounded, size: 20)),
            ]),
        const SizedBox(height: 16),
        if (mac != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许远程控制本机'),
            subtitle: Text(mac.hostingEnabled
                ? mac.captureRunning
                    ? '正在被观看'
                    : '待命中，有人连接时才会共享屏幕'
                : '关闭后其他设备无法连接这台电脑'),
            value: mac.hostingEnabled,
            onChanged: mac.setHostingEnabled,
          )
        else
          OutlinedButton.icon(
            onPressed: () => context.push('/mobile-host'),
            icon: Icon(running ? Icons.tune_rounded : Icons.play_arrow_rounded,
                size: 18),
            label: Text(running ? '管理屏幕共享' : '开始共享屏幕'),
          ),
        if (lan != null && lan.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.lan_rounded, size: 16, color: p.inkTertiary),
            const SizedBox(width: 6),
            Expanded(
                child: Text('局域网直连地址 $lan',
                    style: t.bodySmall, overflow: TextOverflow.ellipsis)),
            TextButton(
                onPressed: () => _copy(lan, '直连地址'), child: const Text('复制')),
          ]),
        ],
      ]),
    );
  }
}

class _HostUnsupportedCard extends StatelessWidget {
  const _HostUnsupportedCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return RdCard(
      padding: const EdgeInsets.all(20),
      radius: Rd.radiusLg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _CardTitle(
            icon: Icons.info_outline_rounded,
            tone: RdTone.neutral,
            title: '这台电脑暂不支持被远程控制',
            subtitle: '当前系统上的随控只能用于控制其他设备'),
        const SizedBox(height: 16),
        Text('需要别人帮你操作时，可以在 Windows、Mac 或安卓设备上打开随控共享屏幕。',
            style: t.bodySmall),
      ]),
    );
  }
}

class _RecentConnections extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _RecentConnections({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final records = context
        .watch<ConnectionProvider>()
        .recentConnections
        .where((r) => seen.add(r.peerId))
        .take(8)
        .toList();
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RdSectionHeader('最近连接',
          trailing: TextButton(
              onPressed: () => context.push('/logs'),
              child: const Text('全部记录'))),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final r in records)
          SizedBox(
            width: 220,
            child: RdCard(
              onTap: () => onPick(r.peerId),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                RdDeviceGlyph(platform: r.peerOs, size: 36),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(r.peerHostname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(formatDeviceId(r.peerId),
                          style: Theme.of(context).textTheme.labelSmall),
                    ])),
              ]),
            ),
          ),
      ]),
    ]);
  }
}
