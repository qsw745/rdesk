import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/utils/remote_key_action.dart';

void main() {
  test('特殊按键映射为固定 macOS 键码', () {
    final escape = macRemoteKeyStrokeForAction('key_escape');
    final left = macRemoteKeyStrokeForAction('key_arrow_left');

    expect(escape?.keyCode, 53);
    expect(escape?.modifiers, isEmpty);
    expect(left?.keyCode, 123);
    expect(left?.modifiers, isEmpty);
  });

  test('组合键同时保留主键和全部修饰键', () {
    final redo = macRemoteKeyStrokeForAction('key_command_shift_z');

    expect(redo?.keyCode, 6);
    expect(
      redo?.modifiers,
      {MacRemoteModifier.command, MacRemoteModifier.shift},
    );
  });

  test('macOS 窗口与桌面动作映射为系统快捷键', () {
    final showAllWindows = macRemoteKeyStrokeForAction('show_all_windows');
    final showDesktop = macRemoteKeyStrokeForAction('show_desktop');

    expect(showAllWindows?.keyCode, 126);
    expect(showAllWindows?.modifiers, {MacRemoteModifier.control});
    expect(showDesktop?.keyCode, 103);
    expect(showDesktop?.modifiers, isEmpty);
  });

  test('未知动作不生成键盘事件', () {
    expect(macRemoteKeyStrokeForAction('key_not_supported'), isNull);
    expect(macRemoteKeyStrokeForAction('wake_screen'), isNull);
  });
}
