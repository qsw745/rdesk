import 'dart:convert';
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
      // Windows 按第一个点之前的部分认设备名。
      expect(sanitizeIncomingFileName('NUL.tar.gz'), '_NUL.tar.gz');
      expect(sanitizeIncomingFileName('com1.a.b'), '_com1.a.b');
      expect(sanitizeIncomingFileName('console.txt'), 'console.txt');
      expect(sanitizeIncomingFileName('..'), '未命名文件');
      expect(sanitizeIncomingFileName('   '), '未命名文件');
    });

    test('过长的名字截短但保留扩展名', () {
      final name = sanitizeIncomingFileName('${'长' * 300}.pdf');

      // 各桌面文件系统的文件名上限是 255 字节，汉字每个占 3 字节。
      expect(utf8.encode(name).length, lessThanOrEqualTo(200));
      expect(name, endsWith('.pdf'));
      expect(name, startsWith('长长长'));
    });

    test('截短不会切开一个字符，也不会留下结尾的点或空格', () {
      final emoji = sanitizeIncomingFileName('${'😀' * 100}.txt');
      expect(() => utf8.encode(emoji), returnsNormally);
      expect(emoji.runes.every((rune) => rune == 0x1F600 || rune < 0x80), isTrue);

      final spaced = sanitizeIncomingFileName('${'a' * 195}  . .b');
      expect(spaced, isNot(matches(RegExp(r'[. ]$'))));
      expect(utf8.encode(spaced).length, lessThanOrEqualTo(200));
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

    test('接收过程中用临时名，完成后才出现最终文件名', () async {
      final seenWhileReceiving = <String>[];
      Stream<List<int>> slow() async* {
        yield [1, 2];
        seenWhileReceiving
            .addAll(dir.listSync().map((e) => e.uri.pathSegments.last));
        yield [3];
      }

      final saved = await store.save('video.mp4', slow(), maxBytes: 10);

      expect(seenWhileReceiving, hasLength(1));
      expect(seenWhileReceiving.single, endsWith('.part'));
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['video.mp4']);
      expect(await saved.file.readAsBytes(), [1, 2, 3]);
    });

    test('两个同名文件同时到达，各自完整保存', () async {
      final results = await Future.wait([
        store.save('a.txt', Stream.fromIterable([[1], [1]]), maxBytes: 10),
        store.save('a.txt', Stream.fromIterable([[2], [2]]), maxBytes: 10),
      ]);

      expect(results.map((r) => r.name).toSet(), {'a.txt', 'a (1).txt'});
      final contents = [
        for (final r in results) await r.file.readAsBytes(),
      ];
      expect(contents, containsAll([[1, 1], [2, 2]]));
      expect(dir.listSync(), hasLength(2));
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
