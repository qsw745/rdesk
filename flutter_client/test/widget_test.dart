import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rdesk/app.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/');
  });

  testWidgets('底部导航和我的设备页可见', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('我的设备'), findsWidgets);
    expect(find.text('云设备'), findsOneWidget);
    expect(find.text('远程连接'), findsOneWidget);
    expect(find.text('地址簿'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('登录注册和移动被控路由可打开', (tester) async {
    await tester.pumpWidget(const RDeskApp());

    appRouter.go('/login?redirect=%2Fcloud');
    await tester.pumpAndSettle();
    expect(find.text('登录账号'), findsWidgets);

    appRouter.go('/register?redirect=%2Fcloud');
    await tester.pumpAndSettle();
    expect(find.text('注册账号'), findsWidgets);

    appRouter.go('/mobile-host');
    await tester.pumpAndSettle();
    expect(find.text('移动被控'), findsOneWidget);
  });
}
