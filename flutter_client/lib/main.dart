import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled startup error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };
  // TODO: Initialize flutter_rust_bridge here
  // await RustLib.init();
  runZonedGuarded(
    () => runApp(const RDeskApp()),
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}
