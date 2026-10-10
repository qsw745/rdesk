import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/key_mapping.dart';
import 'remote_peer_platform.dart';

/// What one hardware key press on the viewer turns into for the remote host.
sealed class RemoteKeyOutput {
  const RemoteKeyOutput();
}

/// Typed characters, sent as text so the remote keyboard layout is irrelevant.
final class RemoteKeyText extends RemoteKeyOutput {
  const RemoteKeyText(this.text);
  final String text;
}

/// A key or key combination, sent through the remote action channel.
final class RemoteKeyAction extends RemoteKeyOutput {
  const RemoteKeyAction(this.action);
  final String action;
}

/// Prefix of a generic key press such as `key:ctrl+shift+z`. Windows hosts
/// understand it from 2.3.8; older hosts report it as unsupported.
const remoteKeyActionPrefix = 'key:';

final _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

/// Keys that are keys rather than characters, by their name in a key action.
final _namedKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.f1: 'f1',
  LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3',
  LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7',
  LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9',
  LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11',
  LogicalKeyboardKey.f12: 'f12',
};

/// Character keys by position, so a combination means the same key whatever
/// the modifiers did to the character (Option+A types "å" on a Mac).
final _positionKeys = <PhysicalKeyboardKey, String>{
  PhysicalKeyboardKey.keyA: 'a',
  PhysicalKeyboardKey.keyB: 'b',
  PhysicalKeyboardKey.keyC: 'c',
  PhysicalKeyboardKey.keyD: 'd',
  PhysicalKeyboardKey.keyE: 'e',
  PhysicalKeyboardKey.keyF: 'f',
  PhysicalKeyboardKey.keyG: 'g',
  PhysicalKeyboardKey.keyH: 'h',
  PhysicalKeyboardKey.keyI: 'i',
  PhysicalKeyboardKey.keyJ: 'j',
  PhysicalKeyboardKey.keyK: 'k',
  PhysicalKeyboardKey.keyL: 'l',
  PhysicalKeyboardKey.keyM: 'm',
  PhysicalKeyboardKey.keyN: 'n',
  PhysicalKeyboardKey.keyO: 'o',
  PhysicalKeyboardKey.keyP: 'p',
  PhysicalKeyboardKey.keyQ: 'q',
  PhysicalKeyboardKey.keyR: 'r',
  PhysicalKeyboardKey.keyS: 's',
  PhysicalKeyboardKey.keyT: 't',
  PhysicalKeyboardKey.keyU: 'u',
  PhysicalKeyboardKey.keyV: 'v',
  PhysicalKeyboardKey.keyW: 'w',
  PhysicalKeyboardKey.keyX: 'x',
  PhysicalKeyboardKey.keyY: 'y',
  PhysicalKeyboardKey.keyZ: 'z',
  PhysicalKeyboardKey.digit0: '0',
  PhysicalKeyboardKey.digit1: '1',
  PhysicalKeyboardKey.digit2: '2',
  PhysicalKeyboardKey.digit3: '3',
  PhysicalKeyboardKey.digit4: '4',
  PhysicalKeyboardKey.digit5: '5',
  PhysicalKeyboardKey.digit6: '6',
  PhysicalKeyboardKey.digit7: '7',
  PhysicalKeyboardKey.digit8: '8',
  PhysicalKeyboardKey.digit9: '9',
  PhysicalKeyboardKey.space: 'space',
  PhysicalKeyboardKey.minus: 'minus',
  PhysicalKeyboardKey.equal: 'equal',
  PhysicalKeyboardKey.bracketLeft: 'bracketleft',
  PhysicalKeyboardKey.bracketRight: 'bracketright',
  PhysicalKeyboardKey.backslash: 'backslash',
  PhysicalKeyboardKey.semicolon: 'semicolon',
  PhysicalKeyboardKey.quote: 'quote',
  PhysicalKeyboardKey.comma: 'comma',
  PhysicalKeyboardKey.period: 'period',
  PhysicalKeyboardKey.slash: 'slash',
  PhysicalKeyboardKey.backquote: 'backquote',
};

/// Actions the macOS host implements, by key.
const _macNamedActions = <String, String>{
  'enter': 'enter',
  'backspace': 'delete',
  'escape': 'key_escape',
  'tab': 'key_tab',
  'left': 'key_arrow_left',
  'right': 'key_arrow_right',
  'up': 'key_arrow_up',
  'down': 'key_arrow_down',
};

bool _isTypedText(String? character) {
  if (character == null || character.isEmpty) return false;
  return character.runes.every((rune) =>
      rune >= 0x20 &&
      rune != 0x7F &&
      // macOS reports keys without a character as private-use code points.
      !(rune >= 0xE000 && rune <= 0xF8FF));
}

/// Translates a hardware key press for [remote], or returns null when that
/// host has no way to perform it. Nothing is ever sent that the host would
/// silently ignore or do differently.
RemoteKeyOutput? translateHardwareKey({
  required RemotePeerPlatform remote,
  required TargetPlatform viewer,
  required PhysicalKeyboardKey physical,
  required LogicalKeyboardKey logical,
  required String? character,
  required bool meta,
  required bool control,
  required bool alt,
  required bool shift,
  WindowsKeyMapping mapping = WindowsKeyMapping.defaults,
}) {
  if (_modifierKeys.contains(logical)) return null;
  final named = _namedKeys[logical];
  final combination = meta || control || alt;
  final fromMac = viewer == TargetPlatform.macOS;

  if (named == null && !combination) {
    return _isTypedText(character) ? RemoteKeyText(character!) : null;
  }
  // Quit, close, hide and minimise belong to the viewer's own window: a
  // session must never make its app impossible to leave from the keyboard.
  if (fromMac &&
      meta &&
      !control &&
      const {'q', 'w', 'h', 'm'}.contains(_positionKeys[physical])) {
    return null;
  }

  switch (remote) {
    case RemotePeerPlatform.windows:
      var key = named ?? _positionKeys[physical];
      if (key == null) return null;
      if (fromMac && key == 'backspace') key = mapping.delete.name;
      if (fromMac && logical == LogicalKeyboardKey.delete) {
        key = mapping.fnDelete.name;
      }
      // On a Mac the modifiers go through the user's mapping; any other
      // keyboard already has the keys Windows expects.
      final pressed = <RemoteModifier>{
        if (meta) fromMac ? mapping.command : RemoteModifier.win,
        if (alt) fromMac ? mapping.option : RemoteModifier.alt,
        if (control) fromMac ? mapping.control : RemoteModifier.ctrl,
      };
      final parts = [
        if (pressed.contains(RemoteModifier.ctrl)) 'ctrl',
        if (pressed.contains(RemoteModifier.alt)) 'alt',
        if (shift) 'shift',
        if (pressed.contains(RemoteModifier.win)) 'win',
        key,
      ];
      return RemoteKeyAction('$remoteKeyActionPrefix${parts.join('+')}');

    case RemotePeerPlatform.mac:
      if (named != null) {
        final action = combination || shift ? null : _macNamedActions[named];
        return action == null ? null : RemoteKeyAction(action);
      }
      // The edit shortcuts: Command on a Mac keyboard, Ctrl elsewhere.
      final primary = fromMac ? meta && !control : control && !meta;
      if (!primary || alt) return null;
      final letter = _positionKeys[physical];
      if (shift) {
        return letter == 'z'
            ? const RemoteKeyAction('key_command_shift_z')
            : null;
      }
      return const {'a', 'c', 'v', 'x', 'z'}.contains(letter)
          ? RemoteKeyAction('key_command_$letter')
          : null;

    case RemotePeerPlatform.android:
    case RemotePeerPlatform.other:
      if (combination || shift) return null;
      return switch (named) {
        'enter' => const RemoteKeyAction('enter'),
        'backspace' => const RemoteKeyAction('delete'),
        _ => null,
      };
  }
}

/// Sends key presses one at a time and in order. Separate requests could
/// overtake each other on the way and scramble what was typed. Characters
/// typed while a request is under way are merged into the next one.
class RemoteKeyQueue {
  RemoteKeyQueue({required this.sendText, required this.sendAction});

  /// Beyond this the connection is not keeping up; more keys are dropped
  /// rather than replayed long after they were pressed.
  static const maxPending = 64;

  final Future<void> Function(String text) sendText;
  final Future<void> Function(String action) sendAction;
  final _pending = <RemoteKeyOutput>[];
  Future<void>? _draining;

  /// Completes when everything queued so far has been sent.
  Future<void> get idle => _draining ?? Future<void>.value();

  void add(RemoteKeyOutput output) {
    if (_pending.length >= maxPending) return;
    final last = _pending.isEmpty ? null : _pending.last;
    if (output is RemoteKeyText && last is RemoteKeyText) {
      _pending[_pending.length - 1] = RemoteKeyText(last.text + output.text);
    } else {
      _pending.add(output);
    }
    _draining ??= _drain();
  }

  void clear() => _pending.clear();

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        try {
          switch (next) {
            case RemoteKeyText(:final text):
              await sendText(text);
            case RemoteKeyAction(:final action):
              await sendAction(action);
          }
        } catch (error) {
          debugPrint('[RDesk] hardware key not sent: ${error.runtimeType}');
        }
      }
    } finally {
      _draining = null;
    }
  }
}
