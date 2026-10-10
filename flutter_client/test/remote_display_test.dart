import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/remote_display.dart';

void main() {
  test('新版被控端报告型号时，每块屏幕按顺序编号并带上型号', () {
    final displays = RemoteDisplay.parseList([
      {
        'index': 0,
        'name': '显示屏 1（VG27AQL3A）',
        'model': 'VG27AQL3A',
        'width': 2560,
        'height': 1440,
        'isMain': true,
      },
      {
        'index': 1,
        'name': '显示屏 2（Built-in Retina Display）',
        'model': 'Built-in Retina Display',
        'width': 1728,
        'height': 1117,
        'isMain': false,
      },
    ]);

    expect(displays.map((d) => d.title), ['显示屏 1', '显示屏 2']);
    expect(displays.map((d) => d.detail),
        ['VG27AQL3A', 'Built-in Retina Display']);
    expect(displays.first.label, '显示屏 1（VG27AQL3A）');
    expect(displays.first.description, '主显示器 · VG27AQL3A · 2560×1440');
    expect(displays.last.description, 'Built-in Retina Display · 1728×1117');
    expect(displays.last.index, 1);
    expect(displays.any((d) => d.isSelected), isFalse);
  });

  test('被控端说明当前显示的是哪块屏', () {
    final displays = RemoteDisplay.parseList([
      {'index': 0, 'selected': false},
      {'index': 1, 'selected': true},
      {'index': 2, 'selected': 'yes'},
    ]);

    expect(displays.map((d) => d.isSelected), [false, true, false]);
  });

  test('旧版被控端只有名称和尺寸时，用分辨率区分屏幕', () {
    final displays = RemoteDisplay.parseList([
      {'index': 0, 'name': '主显示器 (2560×1440)', 'width': 2560, 'height': 1440, 'isMain': true},
      {'index': 1, 'name': '显示器 2 (1728×1117)', 'width': 1728, 'height': 1117, 'isMain': false},
    ]);

    expect(displays.map((d) => d.label), ['显示屏 1（2560×1440）', '显示屏 2（1728×1117）']);
    expect(displays.first.model, isNull);
  });

  test('列表里不合规的内容被跳过或忽略，不会让界面出错', () {
    expect(RemoteDisplay.parseList(null), isEmpty);
    expect(RemoteDisplay.parseList({'name': 'x'}), isEmpty);

    final displays = RemoteDisplay.parseList([
      'not a display',
      {'index': 'two', 'model': '   ', 'width': -5, 'height': 'tall'},
      {'index': 7, 'model': 42},
    ]);

    expect(displays, hasLength(2));
    expect(displays.first.index, 0);
    expect(displays.first.label, '显示屏 1');
    expect(displays.first.description, isEmpty);
    expect(displays.last.index, 7);
    expect(displays.last.title, '显示屏 2');
  });

  test('还不知道对方有哪些屏幕时显示一块主显示器', () {
    expect(RemoteDisplay.fallback.label, '主显示器');
    expect(RemoteDisplay.fallback.index, 0);
  });
}
