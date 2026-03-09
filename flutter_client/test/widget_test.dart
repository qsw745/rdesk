import 'package:flutter_test/flutter_test.dart';

import 'package:rdesk/app.dart';

void main() {
  testWidgets('首页标题可见', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('RDesk 远程桌面'), findsOneWidget);
  });
}
