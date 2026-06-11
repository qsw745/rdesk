import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Unhandled startup error: $error');
        debugPrintStack(stackTrace: stack);
        return true;
      };
      // NOTE: flutter_rust_bridge is NOT initialized yet.
      // rdesk_core (Rust) connection stack is stub-only and will bail!()
      // on connect/start. All real connectivity uses the Flutter HTTP bridge.
      // await RustLib.init();
      runApp(const RDeskApp());
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}
