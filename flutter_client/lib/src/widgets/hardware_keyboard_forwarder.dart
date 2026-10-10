import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/key_mapping.dart';
import '../utils/hardware_key_forwarding.dart';
import '../utils/remote_peer_platform.dart';

/// Forwards the viewer's hardware keyboard to the remote host while [child]
/// has the focus. A text field or sheet that takes the focus keeps its keys.
///
/// Shortcuts the viewer's own system claims first (on a Mac, Command+Tab)
/// never arrive here; quit, close, hide and minimise are left alone on
/// purpose. Both stay local.
class HardwareKeyboardForwarder extends StatefulWidget {
  const HardwareKeyboardForwarder({
    super.key,
    required this.peerOs,
    required this.enabled,
    required this.mapping,
    required this.onText,
    required this.onAction,
    required this.child,
  });

  final String peerOs;

  /// False while the session is view-only.
  final bool enabled;
  final WindowsKeyMapping mapping;
  final Future<void> Function(String text) onText;
  final Future<void> Function(String action) onAction;
  final Widget child;

  @override
  State<HardwareKeyboardForwarder> createState() =>
      _HardwareKeyboardForwarderState();
}

class _HardwareKeyboardForwarderState extends State<HardwareKeyboardForwarder> {
  final _focusNode = FocusNode(debugLabel: 'remote hardware keyboard');
  late final _queue = RemoteKeyQueue(
    sendText: (text) => widget.onText(text),
    sendAction: (action) => widget.onAction(action),
  );

  @override
  void dispose() {
    _queue.clear();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Only when this node itself is focused: a descendant text field that
    // did not use a key must not leak it to the remote computer.
    if (!widget.enabled || !node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final output = translateHardwareKey(
      remote: remotePeerPlatformOf(widget.peerOs),
      viewer: defaultTargetPlatform,
      physical: event.physicalKey,
      logical: event.logicalKey,
      character: event.character,
      meta: keyboard.isMetaPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      mapping: widget.mapping,
    );
    if (output == null) return KeyEventResult.ignored;
    _queue.add(output);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      // Clicking the remote picture hands the keyboard back to it.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_focusNode.hasFocus) _focusNode.requestFocus();
        },
        child: widget.child,
      ),
    );
  }
}
