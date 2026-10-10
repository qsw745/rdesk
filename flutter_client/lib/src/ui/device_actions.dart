import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/device_directory_entry.dart';
import '../models/session.dart';
import '../models/wake.dart';
import '../providers/address_book_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wake_provider.dart';
import '../utils/device_address.dart';
import '../utils/device_directory.dart';
import '../widgets/device_connection_dialog.dart';
import 'components.dart';

/// Every device the user can see: account devices, history, favourites and
/// remote-wake targets merged into one list. Call inside `build`.
List<DeviceDirectoryEntry> watchDeviceDirectory(BuildContext context) {
  final auth = context.watch<AuthProvider>();
  final connection = context.watch<ConnectionProvider>();
  final book = context.watch<AddressBookProvider>();
  final wake = context.watch<WakeProvider>();
  final scope = context.watch<SettingsProvider>().signalingServer;
  return mergeDeviceDirectory(
      endpointScope: scope,
      accountDevices: normalizedEndpointScope(auth.devicesEndpoint) ==
              normalizedEndpointScope(scope)
          ? auth.devices
          : const [],
      history: connection.recentConnections,
      saved: book.allEntries,
      wakeTargets: wake.targets);
}

String devicePath(DeviceDirectoryEntry e) =>
    '/device/${Uri.encodeComponent(e.key)}';

/// Connection history alone does not establish a currently registered device.
bool isPrimaryDevice(DeviceDirectoryEntry e) =>
    e.accountOwned || e.favorite || e.wakeTarget != null;

/// What this build can do with a directory entry. iOS hosts cannot accept
/// input, and Windows hosts only since the build that reports `canHost`.
class DeviceAbilities {
  final bool isLocal, canControl, canWake;
  final String? unsupportedReason;

  /// Short form of [unsupportedReason] for list rows.
  final String? unsupportedLabel;
  const DeviceAbilities._(
      {required this.isLocal,
      required this.canControl,
      required this.canWake,
      this.unsupportedReason,
      this.unsupportedLabel});

  factory DeviceAbilities.of(BuildContext context, DeviceDirectoryEntry e) {
    final local =
        context.read<ConnectionProvider>().localDevice?.deviceId == e.deviceId;
    final platform = rdPlatformOf(e.platform);
    // Only an account snapshot can say a Windows client predates hosting;
    // favourites and history stay connectable by device code.
    final windows = platform == RdPlatform.windows;
    final outdatedWindows = windows && e.canHost == false;
    // Hosting on Windows is opt-in on the PC itself.
    final windowsHostingOff =
        windows && e.canHost == true && e.hosting == false;
    final reason = local
        ? '这是本机'
        : outdatedWindows
            ? '这台电脑上的随控版本较旧，更新后才能被远程控制'
            : windowsHostingOff
                ? '这台电脑未开启远程控制，请在电脑上打开「允许远程控制本机」'
                : platform == RdPlatform.ios
                    ? 'iPhone / iPad 只能共享画面，暂不支持被控制'
                    : null;
    final target = e.wakeTarget;
    return DeviceAbilities._(
        isLocal: local,
        canControl: reason == null,
        canWake: target != null && target.setupComplete,
        unsupportedReason: reason,
        unsupportedLabel: local || reason == null
            ? null
            : outdatedWindows
                ? '更新后才能被远程控制'
                : windowsHostingOff
                    ? '未开启远程控制'
                    : '暂不支持被远程控制');
  }
}

/// Online state is only known for devices of the signed-in account (and wake
/// targets). Other entries may well be online, so they stay connectable.
bool statusKnown(DeviceDirectoryEntry e) =>
    e.accountOwned || e.wakeTarget != null;

bool canConnectNow(DeviceDirectoryEntry e, DeviceAbilities a) =>
    a.canControl && (e.online || !statusKnown(e));

/// Human status for a device, taking remote wake progress into account.
({String label, RdTone tone}) deviceStatus(
    DeviceDirectoryEntry e, WakeProvider wake) {
  final target = e.wakeTarget;
  final latest = target == null ? null : wake.latestRequestForTarget(target);
  if (e.online) return (label: '在线', tone: RdTone.online);
  if (target != null && wake.isWaking(target)) {
    return (label: '正在开机', tone: RdTone.power);
  }
  if (latest?.phase == WakePhase.unconfirmed &&
      DateTime.now().millisecondsSinceEpoch - latest!.createdAtMs < 600000) {
    return (label: '已发送开机信号', tone: RdTone.warning);
  }
  if (!statusKnown(e)) return (label: '按设备码连接', tone: RdTone.neutral);
  return (label: '离线', tone: RdTone.neutral);
}

/// Connect to a directory entry, then open the viewer or the file manager.
final ValueNotifier<String?> connectingDevice = ValueNotifier(null);

Future<void> connectToDevice(BuildContext context, DeviceDirectoryEntry item,
    {bool files = false}) async {
  final connection = context.read<ConnectionProvider>();
  if (connectingDevice.value != null ||
      connection.connectionState == SessionState.connecting) {
    return;
  }
  final settings = context.read<SettingsProvider>();
  final auth = context.read<AuthProvider>();
  final session = context.read<SessionProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final scope = normalizedEndpointScope(settings.signalingServer);
  final token = auth.session?.token;
  if (!isDirectDeviceAddress(item.deviceId) &&
      item.endpointScope != null &&
      item.endpointScope != scope) {
    messenger.showSnackBar(
        const SnackBar(content: Text('这台设备属于另一台服务器，请先在网络设置中切换服务器。')));
    return;
  }
  connectingDevice.value = item.key;
  try {
    final result = await showDialog<DeviceConnectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeviceConnectionDialog(device: item),
    );
    if (result == null) return;
    // The page may have been replaced while the dialog was open (account
    // switched, programmatic navigation): never attach a session to it.
    if (!context.mounted ||
        auth.session?.token != token ||
        normalizedEndpointScope(settings.signalingServer) != scope ||
        ModalRoute.of(context)?.isCurrent != true) {
      await connection.disconnect(result.sessionId);
      return;
    }
    session.setSession(
        SessionInfo(
          sessionId: result.sessionId,
          peerId: item.deviceId,
          peerHostname: item.name,
          peerOs: connection.peerPlatformForSession(result.sessionId) ??
              item.platform,
          state: SessionState.active,
          connectedAt: DateTime.now(),
        ),
        accessPassword: result.password);
    final id = Uri.encodeComponent(result.sessionId);
    context.go(files ? '/files/$id' : '/remote/$id');
  } finally {
    connectingDevice.value = null;
  }
}

Future<void> toggleFavorite(
    BuildContext context, DeviceDirectoryEntry item) async {
  final book = context.read<AddressBookProvider>();
  if (item.favorite) {
    final ids = {item.deviceId, ...item.relatedDeviceIds};
    for (final id in ids) {
      await book.removeEntry(id, endpointScope: item.endpointScope);
    }
  } else {
    await book.addEntry(
        deviceId: item.deviceId,
        alias: item.name,
        platform: item.platform,
        endpointScope: item.endpointScope);
  }
}

/// Sends a wake request; if the bound home helper is offline the provider
/// switches to another online helper first.
Future<void> wakeDevice(BuildContext context, WakeTarget target) async {
  final wake = context.read<WakeProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await wake.wake(target);
  messenger.showSnackBar(SnackBar(
      content: Text(
          ok ? '开机信号已发出，电脑启动并运行随控后会显示在线' : wake.error ?? '开机请求没有发出，请稍后重试')));
}

Future<void> showAddDeviceDialog(BuildContext context) async {
  final id = TextEditingController(), alias = TextEditingController();
  final book = context.read<AddressBookProvider>();
  final scope =
      normalizedEndpointScope(context.read<SettingsProvider>().signalingServer);
  await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('添加设备'),
              content: SizedBox(
                  width: 380,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('输入对方的设备码，添加后可在设备列表中一键连接。'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: id,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: '设备码或直连地址', hintText: '例如 123 456 789')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: alias,
                        decoration:
                            const InputDecoration(labelText: '备注名称（可选）')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () async {
                      final value = id.text.replaceAll(' ', '').trim();
                      if (value.isEmpty) return;
                      await book.addEntry(
                          deviceId: value,
                          alias: alias.text.trim(),
                          endpointScope: scope);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('添加')),
              ]));
  // Let the closing route finish using its editing controllers.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  id.dispose();
  alias.dispose();
}
