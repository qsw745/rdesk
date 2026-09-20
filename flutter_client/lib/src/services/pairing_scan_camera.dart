import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

abstract class PairingScanCamera {
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
  bool get canResume;
  Widget preview(ValueChanged<String> onCode);
}

class MobilePairingScanCamera implements PairingScanCamera {
  final controller = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
      detectionSpeed: DetectionSpeed.noDuplicates);
  @override
  bool get canResume => controller.value.hasCameraPermission;
  @override
  Future<void> start() async {
    await controller.start();
    if (controller.value.error != null) throw controller.value.error!;
  }

  @override
  Future<void> stop() => controller.stop();
  @override
  Future<void> dispose() => controller.dispose();
  @override
  Widget preview(ValueChanged<String> onCode) => MobileScanner(
      controller: controller,
      useAppLifecycleState: false,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null) {
            onCode(value);
            break;
          }
        }
      },
      errorBuilder: (_, __) => const Center(
          child: Text('相机暂不可用，可输入配对码', style: TextStyle(color: Colors.white))),
      placeholderBuilder: (_) => const ColoredBox(
          color: Color(0xff172033),
          child: Center(
              child:
                  Icon(Icons.qr_code_scanner, size: 72, color: Colors.white))));
}
