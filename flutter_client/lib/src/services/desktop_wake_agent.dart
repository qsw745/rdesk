import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class DesktopWakeNetwork {
  final String name, cidr, hardware;
  const DesktopWakeNetwork(this.name, this.cidr, this.hardware);
  Map<String, String> get config =>
      {'interface': name, 'ipv4_cidr': cidr, 'interface_hardware': hardware};
}

/// Runs the bundled, signed helper. Closing the app closes its stdin and stops it.
class DesktopWakeAgent {
  Process? _process;
  int _generation = 0;
  DesktopWakeNetwork? selected;
  bool ready = false;
  String? owner, endpoint, agentId, error;
  bool get enabled => _process != null && ready;
  String get executable =>
      '${File(Platform.resolvedExecutable).parent.parent.path}/Helpers/rdesk-wake-helper';

  Future<List<DesktopWakeNetwork>> networks() async {
    if (!await File(executable).exists())
      throw StateError('此安装包缺少 Mac 开机助手，请安装完整测试版');
    final result = await Process.run(executable, ['app-networks'])
        .timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) throw StateError('无法读取家庭网络，请检查网络连接');
    return (jsonDecode(result.stdout as String) as List)
        .map((v) => DesktopWakeNetwork(v['interface'] as String,
            v['ipv4_cidr'] as String, v['interface_hardware'] as String))
        .toList();
  }

  Future<void> start(
      {required String endpoint,
      required String ownerId,
      required String agentId,
      required String token}) async {
    final network = selected;
    if (network == null) throw StateError('请先选择电脑所在的家庭网络');
    await stop();
    final gen = _generation;
    final root = await getApplicationSupportDirectory();
    if (gen != _generation) throw StateError('助手启动已取消');
    final key = sha256.convert(utf8.encode('$endpoint|$ownerId|$agentId'));
    final dir = Directory('${root.path}/wake-helper/$key');
    await dir.create(recursive: true);
    final mode = await Process.run('/bin/chmod', ['700', dir.path]);
    if (mode.exitCode != 0 || gen != _generation)
      throw StateError('无法准备助手私有目录');
    final process =
        await Process.start(executable, ['app-run', '--state', dir.path]);
    if (gen != _generation) {
      process.kill();
      throw StateError('助手启动已取消');
    }
    _process = process;
    this.endpoint = endpoint;
    owner = ownerId;
    this.agentId = agentId;
    error = null;
    final started = Completer<void>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('开机助手运行中') &&
          gen == _generation &&
          !started.isCompleted) {
        ready = true;
        started.complete();
      }
    });
    // Native diagnostics remain in private files; never expose raw process errors.
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) {
      if (gen == _generation) {
        _process = null;
        ready = false;
        error = '助手已停止，请检查家庭网络后重新启用';
      }
      if (!started.isCompleted)
        started.completeError(StateError('助手启动失败，请检查所选网络'));
    }));
    try {
      process.stdin.writeln(jsonEncode({
        'server': endpoint,
        'agent_id': agentId,
        'token': token,
        ...network.config
      }));
      await process.stdin.flush();
      await started.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    ++_generation;
    final process = _process;
    _process = null;
    ready = false;
    owner = null;
    endpoint = null;
    agentId = null;
    error = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      try {
        await process.stdin.close();
      } catch (_) {}
    }
  }
}
