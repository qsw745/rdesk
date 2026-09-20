import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_update.dart';
import '../services/app_update_service.dart';

enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  opening,
  handedOff,
  failed
}

class AppUpdateProvider extends ChangeNotifier {
  final AppUpdateService service;
  final UpdateTarget target;
  final DateTime Function() now;
  final Future<AppVersion> Function() installedVersion;
  AppUpdateProvider(
      {AppUpdateService? service,
      UpdateTarget? target,
      DateTime Function()? now,
      Future<AppVersion> Function()? installedVersion})
      : service = service ?? AppUpdateService(),
        target = target ?? UpdateTarget.current(),
        now = now ?? DateTime.now,
        installedVersion = installedVersion ??
            (() async {
              final info = await PackageInfo.fromPlatform();
              return AppVersion.parse(
                  info.version, int.tryParse(info.buildNumber));
            });
  SharedPreferences? _prefs;
  Future<void>? _initializing;
  bool _disposed = false;
  Timer? _versionTimer;
  int _downloadGeneration = 0;
  bool automatic = true;
  String? _ignored;
  DateTime _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
  UpdatePhase phase = UpdatePhase.idle;
  UpdateRelease? release;
  AppVersion? current;
  File? package;
  int received = 0;
  String? message;
  bool installPermissionRequired = false;
  bool get busy => const [
        UpdatePhase.checking,
        UpdatePhase.downloading,
        UpdatePhase.opening
      ].contains(phase);
  bool get showBanner =>
      release != null &&
      release!.key != _ignored &&
      phase != UpdatePhase.current &&
      phase != UpdatePhase.idle;
  double? get progress =>
      release?.bytes == null ? null : received / release!.bytes!;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= (() async {
        _prefs = await SharedPreferences.getInstance();
        automatic = _prefs!.getBool('updates.automatic') ?? true;
        _ignored = _prefs!.getString('updates.ignored');
        _nextCheck = DateTime.fromMillisecondsSinceEpoch(
            _prefs!.getInt('updates.nextCheck') ?? 0);
        final cached = _prefs!.getString('updates.manifest');
        if (cached != null && cached.length <= 128 * 1024) {
          try {
            final found = UpdateRelease.fromManifest(
                jsonDecode(cached) as Map<String, dynamic>, target);
            current = await _readInstalledVersion();
            if (!_disposed && found.version.compareTo(current!) > 0) {
              release = found;
              phase = UpdatePhase.available;
            }
          } catch (_) {
            /* Ignore invalid cache and revalidate on the next check. */
          }
        }
        _notify();
      })();

  Future<AppVersion> _readInstalledVersion() async {
    final result = Completer<AppVersion>();
    _versionTimer = Timer(const Duration(seconds: 10), () {
      if (!result.isCompleted)
        result.completeError(const UpdateFailure('无法读取当前版本，请重试'));
    });
    installedVersion().then((value) {
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    try {
      return await result.future;
    } finally {
      _versionTimer?.cancel();
      _versionTimer = null;
    }
  }

  Future<void> setAutomatic(bool value) async {
    await initialize();
    automatic = value;
    _notify();
    await _prefs!.setBool('updates.automatic', value);
    if (value) await check();
  }

  Future<void> ignore() async {
    await initialize();
    _ignored = release?.key;
    if (_ignored != null) await _prefs!.setString('updates.ignored', _ignored!);
    _notify();
  }

  Future<void> check({bool manual = false}) async {
    await initialize();
    if (_disposed ||
        busy ||
        (!manual && (!automatic || now().isBefore(_nextCheck)))) return;
    phase = UpdatePhase.checking;
    if (manual) _ignored = null;
    message = null;
    _notify();
    try {
      current ??= await _readInstalledVersion();
      if (_disposed) return;
      final found = await service.check(target);
      if (_disposed) return;
      if (release?.key != found.key) {
        await _removePackage();
        release = null;
      }
      if (found.version.compareTo(current!) > 0) {
        release = found;
        phase = package != null ? UpdatePhase.ready : UpdatePhase.available;
      } else {
        release = null;
        phase = UpdatePhase.current;
        message = found.version.compareTo(current!) < 0
            ? '当前安装版本高于${found.isStore ? '商店' : '公开'}版本（${found.version}），无需降级'
            : '当前已是最新版本';
      }
      await _prefs!
          .setString('updates.manifest', jsonEncode(found.toManifest()));
      _nextCheck = now().add(const Duration(hours: 6));
    } catch (error) {
      if (_disposed) return;
      phase = UpdatePhase.failed;
      message = _friendly(error, '暂时无法检查更新，请确认网络后重试');
      _nextCheck = now().add(const Duration(hours: 1));
    }
    await _prefs!
        .setInt('updates.nextCheck', _nextCheck.millisecondsSinceEpoch);
    _notify();
  }

  Future<void> download() async {
    final selected = release;
    if (_disposed || busy || selected == null || selected.isStore) return;
    final generation = ++_downloadGeneration;
    phase = UpdatePhase.downloading;
    received = 0;
    message = null;
    installPermissionRequired = false;
    _notify();
    try {
      await _removePackage();
      if (_disposed || generation != _downloadGeneration)
        throw const UpdateCancelled();
      final file = await service.download(selected, (bytes) {
        received = bytes;
        _notify();
      });
      if (_disposed || generation != _downloadGeneration) {
        await file.parent.delete(recursive: true);
        throw const UpdateCancelled();
      }
      package = file;
      phase = UpdatePhase.ready;
      message = '安装包已下载并通过校验';
    } on UpdateCancelled {
      phase = UpdatePhase.available;
      message = '下载已取消';
    } catch (error) {
      phase = UpdatePhase.failed;
      message = _friendly(error, '下载失败，请检查网络后重新下载');
    }
    _notify();
  }

  void cancelDownload() {
    _downloadGeneration++;
    service.cancelDownload();
  }

  Future<void> install({required bool sessionActive}) async {
    if (_disposed || busy || release == null) return;
    if (sessionActive) {
      message = '请先结束远程会话，再安装更新';
      _notify();
      return;
    }
    phase = UpdatePhase.opening;
    _notify();
    try {
      final result = await service.openInstaller(release!, package);
      if (_disposed) return;
      installPermissionRequired = result == 'permission_required';
      if (result != 'opened' &&
          result != 'store' &&
          !installPermissionRequired) {
        throw const UpdateFailure('无法打开系统安装程序');
      }
      phase =
          installPermissionRequired ? UpdatePhase.ready : UpdatePhase.handedOff;
      message = installPermissionRequired
          ? '请允许 RDesk 安装应用，返回后再次点击安装'
          : result == 'store'
              ? '已打开 App Store，请在商店完成更新'
              : target.platform == 'macos'
                  ? '已打开安装包，请将 RDesk 拖入「应用程序」并替换旧版，再重新打开'
                  : '已打开系统安装程序，请按提示完成更新后重新打开 RDesk';
    } catch (error) {
      if (_disposed) return;
      phase = UpdatePhase.failed;
      message = _friendly(error, '无法安装更新，请重新下载后重试');
    }
    _notify();
  }

  Future<void> openInstallSettings() async {
    try {
      await service.openInstallSettings();
    } catch (_) {
      message = '无法打开设置，请在系统设置中允许 RDesk 安装应用';
      _notify();
    }
  }

  String _friendly(Object error, String fallback) =>
      error is UpdateFailure ? error.message : fallback;
  Future<void> _removePackage() async {
    final old = package;
    package = null;
    if (old != null && await old.parent.exists())
      await old.parent.delete(recursive: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _versionTimer?.cancel();
    _downloadGeneration++;
    service.dispose();
    // Completed installers stay available to the system installer until cache cleanup.
    super.dispose();
  }
}
