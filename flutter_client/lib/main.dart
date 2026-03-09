import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Initialize flutter_rust_bridge here
  // await RustLib.init();
  runApp(const RDeskApp());
}
