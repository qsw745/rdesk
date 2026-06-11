import 'package:flutter_test/flutter_test.dart';

import 'package:rdesk/app.dart';

void main() {
  testWidgets('底部导航和我的设备页可见', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('我的设备'), findsWidgets);
    expect(find.text('云设备'), findsOneWidget);
    expect(find.text('远程协助'), findsOneWidget);
    expect(find.text('本机信息'), findsOneWidget);
  });
}
