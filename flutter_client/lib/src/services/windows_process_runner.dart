import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'wake_api.dart';

/// Owns each process until exit, including cancellation and output-limit failures.
class WindowsProcessRunner {
  final Future<Process> Function(String, List<String>) _start;
  final Map<Process, Completer<ProcessResult>> _active = {};
  final Future<void> Function(Process)? _terminateTree;
  final Map<Process, Future<void>> _terminating = {};
  bool _disposed = false;
  WindowsProcessRunner(
      {Future<Process> Function(String, List<String>)? start,
      Future<void> Function(Process)? terminateTree})
      : _start = start ?? ((exe, args) => Process.start(exe, args)),
        _terminateTree = terminateTree;

  Future<ProcessResult> run(String executable, List<String> arguments,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_disposed) throw const WakeApiException('process_cancelled', '检测已取消');
    var args = List<String>.of(arguments);
    if (executable.toLowerCase() == 'powershell.exe') {
      final index = args.indexOf('-Command');
      if (index < 0 || index != args.length - 2) {
        throw const WakeApiException('process_arguments', '检测命令不正确');
      }
      final script =
          "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(\$false); \$OutputEncoding=[Console]::OutputEncoding;\n${args.last}";
      final bytes = <int>[];
      for (final unit in script.codeUnits) {
        bytes.add(unit & 255);
        bytes.add(unit >> 8);
      }
      args = [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        base64Encode(bytes)
      ];
    }
    final process = await _start(executable, args);
    if (_disposed) {
      await _terminate(process);
      await process.exitCode;
      throw const WakeApiException('process_cancelled', '检测已取消');
    }
    final interrupted = Completer<ProcessResult>();
    _active[process] = interrupted;
    final out = <int>[], err = <int>[];
    void fail(String code, String message) {
      if (!interrupted.isCompleted) {
        interrupted.completeError(WakeApiException(code, message));
      }
      unawaited(_stop(process));
    }

    final done = () async {
      // Drain both pipes concurrently to avoid blocking a full stderr pipe.
      Future<void> drain(Stream<List<int>> stream, List<int> dest) async {
        await for (final bytes in stream) {
          if (out.length + err.length + bytes.length > 65536) {
            fail('process_output_limit', '检测输出过大，请重试');
          } else {
            dest.addAll(bytes);
          }
        }
      }

      await Future.wait(
          [drain(process.stdout, out), drain(process.stderr, err)]);
      final code = await process.exitCode;
      String decode(List<int> bytes) =>
          utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
      try {
        return ProcessResult(process.pid, code, decode(out), decode(err));
      } on FormatException {
        throw const WakeApiException('process_encoding', '检测输出编码不正确');
      }
    }();
    final timer = Timer(timeout, () => fail('process_timeout', '检测超时，请重试'));
    try {
      return await Future.any([done, interrupted.future]);
    } finally {
      timer.cancel();
      // Retain ownership until tree termination finishes, including failure paths.
      await _terminating[process];
      await process.exitCode;
      _active.remove(process);
      _terminating.remove(process);
    }
  }

  Future<void> _stop(Process process) =>
      _terminating.putIfAbsent(process, () => _terminate(process));

  Future<void> _terminate(Process process) async {
    if (_terminateTree != null) {
      await _terminateTree(process);
      return;
    }
    if (Platform.isWindows) {
      // powercfg is a short-lived child of the inspection script; terminate the
      // whole tree so a stalled child cannot retain inherited output pipes.
      try {
        final killer = await Process.start(
            'taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
        await Future.wait([
          killer.stdout.drain<void>(),
          killer.stderr.drain<void>(),
          killer.exitCode
        ]).timeout(const Duration(seconds: 3), onTimeout: () {
          killer.kill();
          return <dynamic>[];
        });
      } catch (_) {/* Fall back to terminating the owned process. */}
    }
    process.kill(ProcessSignal.sigkill);
  }

  Future<void> dispose() async {
    _disposed = true;
    final active = Map<Process, Completer<ProcessResult>>.of(_active);
    for (final entry in active.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
            const WakeApiException('process_cancelled', '检测已取消'));
      }
      unawaited(_stop(entry.key));
    }
    await Future.wait(active.keys.map((p) async {
      await _terminating[p];
      await p.exitCode;
    }));
  }
}
