import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/remote_display.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/session_provider.dart';

const _two = [
  RemoteDisplay(index: 0, title: '显示屏 1', model: 'VG27AQL3A', isMain: true),
  RemoteDisplay(index: 1, title: '显示屏 2', model: 'Built-in Retina Display'),
];

SessionInfo _session(String id) => SessionInfo(
      sessionId: id,
      peerId: '123456789',
      peerHostname: 'Mac',
      peerOs: 'macos',
      state: SessionState.active,
      connectedAt: DateTime.now(),
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // What the other computer answers, in order; null is a failed request.
  late List<List<RemoteDisplay>?> answers;
  late List<String> switched;
  var switchAccepted = true;
  var fetches = 0;

  SessionProvider provider() {
    switched = [];
    fetches = 0;
    switchAccepted = true;
    final session = SessionProvider(
      fetchDisplays: (_) async {
        fetches++;
        return answers.isEmpty ? null : answers.removeAt(0);
      },
      switchMonitor: (_, action) async {
        switched.add(action);
        return switchAccepted;
      },
      displayRetryDelay: const Duration(milliseconds: 5),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('连上后列出对方的全部屏幕', () async {
    answers = [_two];
    final session = provider()..setSession(_session('s'));
    expect(session.displays.single.title, '主显示器');

    await _settle();

    expect(session.displays.map((d) => d.title), ['显示屏 1', '显示屏 2']);
    expect(session.availableMonitors,
        ['显示屏 1（VG27AQL3A）', '显示屏 2（Built-in Retina Display）']);
    expect(fetches, 1);
  });

  test('取列表失败不等于只有一块屏幕：稍后重试，成功后显示全部', () async {
    answers = [null, null, _two];
    final session = provider()..setSession(_session('s'));

    await _settle();

    expect(fetches, 3);
    expect(session.displays, hasLength(2));
  });

  test('一直取不到时有限次重试后停下，保留一块主显示器', () async {
    answers = [];
    final session = provider()..setSession(_session('s'));

    await _settle();
    final attempts = fetches;
    await _settle();

    expect(attempts, greaterThan(1));
    expect(fetches, attempts);
    expect(session.displays.single.title, '主显示器');
  });

  test('对方说没有可列出的屏幕时不再重试', () async {
    answers = [const []];
    final session = provider()..setSession(_session('s'));

    await _settle();

    expect(fetches, 1);
    expect(session.displays.single.title, '主显示器');
  });

  test('切换屏幕按对方的编号发送，对方确认后才算切换成功', () async {
    answers = [
      const [
        RemoteDisplay(index: 0, title: '显示屏 1'),
        RemoteDisplay(index: 3, title: '显示屏 2'),
      ]
    ];
    final session = provider()..setSession(_session('s'));
    await _settle();

    expect(await session.setMonitor(1), isTrue);

    expect(switched, ['switch_monitor_3']);
    expect(session.currentMonitor, 1);
  });

  test('对方没有切换时，选中的标签回到原来那块屏幕', () async {
    answers = [_two];
    final session = provider()..setSession(_session('s'));
    await _settle();
    switchAccepted = false;

    expect(await session.setMonitor(1), isFalse);

    expect(session.currentMonitor, 0);
  });

  test('上一位观看者切到了第二块屏：新连上时标签跟着对方当前显示的那块', () async {
    answers = [
      const [
        RemoteDisplay(index: 0, title: '显示屏 1'),
        RemoteDisplay(index: 1, title: '显示屏 2', isSelected: true),
      ]
    ];
    final session = provider()..setSession(_session('s'));

    await _settle();

    expect(session.currentMonitor, 1);
    expect(switched, isEmpty);
  });

  test('一次切换还没有结果时，再点别的屏幕不会发出第二条指令', () async {
    answers = [
      const [
        RemoteDisplay(index: 0, title: '显示屏 1'),
        RemoteDisplay(index: 1, title: '显示屏 2'),
        RemoteDisplay(index: 2, title: '显示屏 3'),
      ]
    ];
    final pending = Completer<bool>();
    switched = [];
    final session = SessionProvider(
      fetchDisplays: (_) async => answers.removeAt(0),
      switchMonitor: (_, action) {
        switched.add(action);
        return pending.future;
      },
    );
    addTearDown(session.dispose);
    session.setSession(_session('s'));
    await _settle();

    final first = session.setMonitor(1);
    expect(await session.setMonitor(2), isFalse);
    expect(switched, ['switch_monitor_1']);
    expect(session.currentMonitor, 1);

    // 对方最终没有切换：回到确认过的那块，而不是停在半路。
    pending.complete(false);
    expect(await first, isFalse);
    expect(session.currentMonitor, 0);
    expect(await session.setMonitor(2), isFalse);
    expect(switched, ['switch_monitor_1', 'switch_monitor_2']);
  });

  test('不存在的屏幕不会发出切换指令', () async {
    answers = [_two];
    final session = provider()..setSession(_session('s'));
    await _settle();

    expect(await session.setMonitor(5), isFalse);
    expect(await session.setMonitor(-1), isFalse);

    expect(switched, isEmpty);
    expect(session.currentMonitor, 0);
  });

  test('换到另一台电脑后，屏幕列表和选中的屏幕重新开始', () async {
    answers = [_two, null, null, null, null, null];
    final session = provider()..setSession(_session('first'));
    await _settle();
    await session.setMonitor(1);

    session.setSession(_session('second'));

    expect(session.currentMonitor, 0);
    expect(session.displays.single.title, '主显示器');
  });
}
