import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/windows_process_runner.dart';
import 'package:rdesk/src/services/wake_api.dart';

void main() {
  test('PowerShell 使用编码参数并保留中文及去除 BOM', () async {
    final runner = WindowsProcessRunner(start: (exe, args) {
      expect(exe, 'powershell.exe');
      expect(args, contains('-EncodedCommand'));
      final bytes = base64Decode(args.last);
      final units = List.generate(
          bytes.length ~/ 2, (i) => bytes[i * 2] | bytes[i * 2 + 1] << 8);
      expect(String.fromCharCodes(units), contains("Write-Output '中文网卡'"));
      return Process.start('/usr/bin/python3', [
        '-c',
        "import sys; sys.stdout.buffer.write('\\ufeff中文网卡'.encode('utf-8'))"
      ]);
    });
    addTearDown(runner.dispose);
    final result = await runner.run(
        'powershell.exe', ['-NoProfile', '-Command', "Write-Output '中文网卡'"]);
    expect(result.stdout, '中文网卡');
  });
  test('非零退出保留退出码', () async {
    final runner = WindowsProcessRunner();
    addTearDown(runner.dispose);
    final result =
        await runner.run('/usr/bin/python3', ['-c', 'import sys; sys.exit(7)']);
    expect(result.exitCode, 7);
  });
  test('超时实际终止进程，不遗留后台任务', () async {
    late Process child;
    final runner = WindowsProcessRunner(start: (exe, args) async {
      child = await Process.start(exe, args);
      return child;
    });
    addTearDown(runner.dispose);
    await expectLater(
        runner.run('/usr/bin/python3', ['-c', 'import time; time.sleep(60)'],
            timeout: const Duration(milliseconds: 100)),
        throwsA(isA<WakeApiException>()
            .having((e) => e.code, 'code', 'process_timeout')));
    expect(await child.exitCode.timeout(const Duration(seconds: 2)), isNonZero);
  });
  test('输出超限会终止，不无限缓存', () async {
    final runner = WindowsProcessRunner();
    addTearDown(runner.dispose);
    await expectLater(
        runner.run('/usr/bin/python3', ['-c', "print('x'*70000)"]),
        throwsA(isA<WakeApiException>()
            .having((e) => e.code, 'code', 'process_output_limit')));
  });
  test('销毁时取消检测并拒绝后续启动', () async {
    final started = Completer<void>();
    late Process child;
    final runner = WindowsProcessRunner(start: (exe, args) async {
      child = await Process.start(exe, args);
      started.complete();
      return child;
    });
    final pending =
        runner.run('/usr/bin/python3', ['-c', 'import time; time.sleep(60)']);
    final assertion = expectLater(
        pending,
        throwsA(isA<WakeApiException>()
            .having((e) => e.code, 'code', 'process_cancelled')));
    await started.future;
    await runner.dispose();
    await assertion;
    expect(await child.exitCode.timeout(const Duration(seconds: 2)), isNonZero);
    await expectLater(
        runner.run('/usr/bin/true', []), throwsA(isA<WakeApiException>()));
  });
}
