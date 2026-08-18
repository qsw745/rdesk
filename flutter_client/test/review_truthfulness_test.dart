import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rdesk/app.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/utils/router.dart';
import 'package:rdesk/src/widgets/remote_control_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/');
  });

  testWidgets('远控操作面板不显示仅本地保存的会话聊天', (tester) async {
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteActionSheet(
              sessionId: 'review-session',
              onDisconnect: () {},
              onFileManager: () {},
              onToggleToolbar: () {},
              onRemoteAction: (_) async {},
              onPushClipboard: () async {},
              onPullClipboard: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('文件传输'), findsOneWidget);
    expect(find.text('会话聊天'), findsNothing);
  });

  testWidgets('我的页不显示未实现的快捷键入口', (tester) async {
    appRouter.go('/me');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('操作手势'), findsOneWidget);
    expect(find.text('快捷键'), findsNothing);
  });
}
