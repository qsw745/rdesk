import 'package:rdesk/src/services/desktop_host_service.dart';

/// Stands in for the real host service in tests. The real one injects mouse
/// and keyboard input into the machine running the tests and reads its
/// clipboard, so no host test may use it for input.
class RecordingHostService extends DesktopHostService {
  RecordingHostService() : super.forTesting();

  /// What a viewer asked for, in order.
  final inputs = <String>[];
  String clipboard = '';

  @override
  Future<bool> performRemoteTap({
    required double normalizedX,
    required double normalizedY,
  }) async {
    inputs.add('tap $normalizedX,$normalizedY');
    return true;
  }

  @override
  Future<bool> performRemoteLongPress({
    required double normalizedX,
    required double normalizedY,
  }) async {
    inputs.add('longPress $normalizedX,$normalizedY');
    return true;
  }

  @override
  Future<bool> performRemoteDrag({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    inputs.add('drag $startX,$startY -> $endX,$endY');
    return true;
  }

  @override
  Future<bool> performRemoteDragPath(List<List<double>> points) async {
    inputs.add('dragPath ${points.length}');
    return true;
  }

  @override
  Future<bool> performRemoteTextInput(String text) async {
    inputs.add('text $text');
    return true;
  }

  @override
  Future<bool> performRemoteAction(String action) async {
    inputs.add('action $action');
    return true;
  }

  @override
  Future<bool> setClipboardText(String text) async {
    clipboard = text;
    inputs.add('clipboardSet');
    return true;
  }

  @override
  Future<String?> getClipboardText() async {
    inputs.add('clipboardGet');
    return clipboard;
  }

  @override
  Future<void> activateAppWindow() async {}
}
