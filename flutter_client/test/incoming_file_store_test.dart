import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/incoming_file_store.dart';

void main() {
  group('文件名', () {
    test('只保留最后一段，路径无法把文件带出接收目录', () {
      expect(sanitizeIncomingFileName('../../Windows/System32/a.dll'), 'a.dll');
      expect(sanitizeIncomingFileName(r'C:\Users\x\合同 v2.docx'), '合同 v2.docx');
      expect(sanitizeIncomingFileName('/etc/passwd'), 'passwd');
    });

    test('去掉 Windows 不允许的字符、控制字符和结尾的点与空格', () {
      expect(sanitizeIncomingFileName('a<b>c:d"e|f?g*.txt'), 'abcdefg.txt');
      expect(sanitizeIncomingFileName('note\u0000\n.txt'), 'note.txt');
      expect(sanitizeIncomingFileName('report. . '), 'report');
    });

    test('设备保留名和空名字换成可用的名字', () {
      expect(sanitizeIncomingFileName('CON'), '_CON');
      expect(sanitizeIncomingFileName('nul.txt'), '_nul.txt');
      expect(sanitizeIncomingFileName('..'), '未命名文件');
      expect(sanitizeIncomingFileName('   '), '未命名文件');
    });

    test('过长的名字截短但保留扩展名', () {
      final name = sanitizeIncomingFileName('${'长' * 300}.pdf');

      expect(name.length, lessThanOrEqualTo(120));
      expect(name, endsWith('.pdf'));
    });
  });

  group('保存', () {
    late Directory dir;
    late IncomingFileStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rdesk-incoming-test');
      store = IncomingFileStore(directory: () async => dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('写入接收目录并返回最终文件名', () async {
      final saved = await store.save(
          '../report.pdf', Stream.value([1, 2, 3]),
          maxBytes: 10);

      expect(saved.name, 'report.pdf');
      expect(saved.file.parent.path, dir.path);
      expect(await saved.file.readAsBytes(), [1, 2, 3]);
    });

    test('同名文件不覆盖，自动加序号', () async {
      await store.save('a.txt', Stream.value([1]), maxBytes: 10);
      final second = await store.save('a.txt', Stream.value([2]), maxBytes: 10);
      final third = await store.save('a.txt', Stream.value([3]), maxBytes: 10);

      expect(second.name, 'a (1).txt');
      expect(third.name, 'a (2).txt');
      expect(await File('${dir.path}/a.txt').readAsBytes(), [1]);
    });

    test('超过大小上限时中止，不留下半个文件', () async {
      await expectLater(
          store.save('big.bin',
              Stream.fromIterable([List.filled(8, 0), List.filled(8, 0)]),
              maxBytes: 10),
          throwsA(isA<IncomingFileTooLarge>()));

      expect(dir.listSync(), isEmpty);
    });

    test('传输中途出错时不留下半个文件', () async {
      Stream<List<int>> broken() async* {
        yield [1, 2];
        throw const SocketException('reset');
      }

      await expectLater(store.save('x.bin', broken(), maxBytes: 10),
          throwsA(isA<SocketException>()));

      expect(dir.listSync(), isEmpty);
    });
  });
}
