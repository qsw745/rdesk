import 'package:flutter_test/flutter_test.dart';

import 'package:rdesk/app.dart';

void main() {
  testWidgets('首页标题可见', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('RDesk'), findsOneWidget);
    expect(find.text('连接远程设备'), findsOneWidget);
  });
}
