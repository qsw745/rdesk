import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/file_entry.dart';
import 'package:rdesk/src/providers/file_transfer_provider.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sent = <String>[];
  Future<void>? cancelSignal;
  Completer<FileSendResult>? pending;
  Object? failure;

  FileTransferProvider provider() {
    sent.clear();
    cancelSignal = null;
    pending = null;
    failure = null;
    final provider = FileTransferProvider(
        send: (sessionId, path, {cancelled}) {
      sent.add(path);
      cancelSignal = cancelled;
      final error = failure;
      if (error != null) throw error;
      return pending?.future ??
          Future.value(const FileSendResult(FileSendOutcome.saved));
    });
    addTearDown(provider.dispose);
    return provider;
  }

  test('对方确认保存后，条目才算完成', () async {
    final files = provider();

    final result = await files.uploadFile('s', '/tmp/a.txt', '/a.txt');

    expect(result.saved, isTrue);
    expect(sent, ['/tmp/a.txt']);
    expect(files.transfers.single.state, TransferState.completed);
  });

  test('仅观看时不发送，也不留下传输条目', () async {
    final files = provider()..viewOnly = true;

    final result = await files.uploadFile('s', '/tmp/a.txt', '/a.txt');

    expect(result.outcome, FileSendOutcome.viewOnly);
    expect(sent, isEmpty);
    expect(files.transfers, isEmpty);
  });

  test('取消会真的中止发送，条目保持已取消', () async {
    final files = provider();
    final waiting = pending = Completer<FileSendResult>();
    final upload = files.uploadFile('s', '/tmp/a.txt', '/a.txt');
    await Future<void>.delayed(Duration.zero);
    var aborted = false;
    unawaited(cancelSignal!.then((_) => aborted = true));

    files.cancelTransfer(files.transfers.single.id);
    await Future<void>.delayed(Duration.zero);

    expect(aborted, isTrue);
    waiting.complete(const FileSendResult(FileSendOutcome.cancelled));
    await upload;
    expect(files.transfers.single.state, TransferState.cancelled);
  });

  test('发送过程抛出异常时条目标为失败，不会一直显示传输中', () async {
    final files = provider();
    failure = const FileSystemException('gone');

    final result = await files.uploadFile('s', '/tmp/a.txt', '/a.txt');

    expect(result.outcome, FileSendOutcome.failed);
    expect(files.transfers.single.state, TransferState.failed);
  });
}
