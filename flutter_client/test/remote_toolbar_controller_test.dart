import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/utils/remote_toolbar_controller.dart';

void main() {
  test('开启自动隐藏后在五秒无操作时收起工具栏', () {
    fakeAsync((async) {
      final controller = RemoteToolbarController();
      addTearDown(controller.dispose);

      controller.setAutoHide(true);
      async.elapse(const Duration(milliseconds: 4999));
      expect(controller.visible, isTrue);

      async.elapse(const Duration(milliseconds: 1));
      expect(controller.visible, isFalse);
    });
  });

  test('新的操作会重新计算自动隐藏时间', () {
    fakeAsync((async) {
      final controller = RemoteToolbarController();
      addTearDown(controller.dispose);

      controller.setAutoHide(true);
      async.elapse(const Duration(seconds: 4));
      controller.markInteraction();
      async.elapse(const Duration(seconds: 4));
      expect(controller.visible, isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(controller.visible, isFalse);
    });
  });

  test('关闭自动隐藏会取消等待中的收起任务', () {
    fakeAsync((async) {
      final controller = RemoteToolbarController();
      addTearDown(controller.dispose);

      controller.setAutoHide(true);
      async.elapse(const Duration(seconds: 4));
      controller.setAutoHide(false);
      async.elapse(const Duration(seconds: 2));

      expect(controller.visible, isTrue);
      expect(controller.autoHide, isFalse);
    });
  });
}
