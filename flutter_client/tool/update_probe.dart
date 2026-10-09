import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rdesk/src/models/app_update.dart';
import 'package:rdesk/src/services/app_update_service.dart';

// Native release-build probe. It never starts a host or reads account state.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: UpdateProbe()));
}

class UpdateProbe extends StatefulWidget {
  const UpdateProbe({super.key});
  @override
  State<UpdateProbe> createState() => _UpdateProbeState();
}

class _UpdateProbeState extends State<UpdateProbe> {
  final service = AppUpdateService();
  String status = '等待检查原生缓存路径和官网下载';
  bool running = false;

  void report(String message) {
    debugPrint('[UpdateProbe] $message');
    if (mounted) setState(() => status = message);
  }

  Future<void> probe() async {
    setState(() => running = true);
    try {
      report('读取原生缓存目录');
      await getTemporaryDirectory();
      await getApplicationSupportDirectory();
      report('缓存和应用支持路径读取成功；检查官网清单');
      final release = await service.check(UpdateTarget.current());
      report('下载 ${release.filename}');
      final file = await service.download(release, (bytes) {
        if (mounted) setState(() => status = '已下载 $bytes / ${release.bytes}');
      });
      await service.verify(file, release);
      report('下载并校验成功：${release.filename}');
    } catch (error, stack) {
      report('${error.runtimeType}: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('随控更新诊断', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 24),
            SelectableText(status),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: running ? null : probe,
                child: const Text('验证缓存和下载')),
          ]),
        ),
      );

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}
