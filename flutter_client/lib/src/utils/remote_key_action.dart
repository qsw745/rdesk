enum MacRemoteModifier { command, control, option, shift }

class MacRemoteKeyStroke {
  const MacRemoteKeyStroke(this.keyCode, [this.modifiers = const {}]);

  final int keyCode;
  final Set<MacRemoteModifier> modifiers;
}

MacRemoteKeyStroke? macRemoteKeyStrokeForAction(String action) {
  return switch (action) {
    'key_escape' => const MacRemoteKeyStroke(53),
    'key_tab' => const MacRemoteKeyStroke(48),
    'key_space' => const MacRemoteKeyStroke(49),
    'key_arrow_left' => const MacRemoteKeyStroke(123),
    'key_arrow_right' => const MacRemoteKeyStroke(124),
    'key_arrow_down' => const MacRemoteKeyStroke(125),
    'key_arrow_up' => const MacRemoteKeyStroke(126),
    'key_command_a' => const MacRemoteKeyStroke(0, {MacRemoteModifier.command}),
    'key_command_c' => const MacRemoteKeyStroke(8, {MacRemoteModifier.command}),
    'key_command_v' => const MacRemoteKeyStroke(9, {MacRemoteModifier.command}),
    'key_command_x' => const MacRemoteKeyStroke(7, {MacRemoteModifier.command}),
    'key_command_z' => const MacRemoteKeyStroke(6, {MacRemoteModifier.command}),
    'key_command_shift_z' => const MacRemoteKeyStroke(
        6,
        {MacRemoteModifier.command, MacRemoteModifier.shift},
      ),
    _ => null,
  };
}

/// Arguments for Windows `shutdown.exe` for a remote power action, or null
/// when [action] is not one. The short delay lets Windows show the person
/// at the computer what is about to happen; nothing is forced, so an
/// application with unsaved work can still hold the shutdown.
List<String>? windowsPowerArguments(String action) {
  const delaySeconds = '10';
  return switch (action) {
    'power_restart' => const ['/r', '/t', delaySeconds, '/c', '随控：远程重启'],
    'power_shutdown' => const ['/s', '/t', delaySeconds, '/c', '随控：远程关机'],
    _ => null,
  };
}

enum WindowsRemoteModifier { control, shift, alt, win }

class WindowsRemoteKeyStroke {
  const WindowsRemoteKeyStroke(this.virtualKey, [this.modifiers = const {}]);

  /// Windows virtual-key code (`VK_*`).
  final int virtualKey;
  final Set<WindowsRemoteModifier> modifiers;
}

/// Viewer action names are shared across hosts, so the `key_command_*`
/// family maps to Ctrl here. `back` / `home` / `recents` come from viewers
/// that predate Windows hosting and still show the mobile bar.
WindowsRemoteKeyStroke? windowsRemoteKeyStrokeForAction(String action) {
  const control = {WindowsRemoteModifier.control};
  const win = {WindowsRemoteModifier.win};
  return switch (action) {
    'key_escape' => const WindowsRemoteKeyStroke(0x1B),
    'key_tab' => const WindowsRemoteKeyStroke(0x09),
    'key_space' => const WindowsRemoteKeyStroke(0x20),
    'key_arrow_left' => const WindowsRemoteKeyStroke(0x25),
    'key_arrow_up' => const WindowsRemoteKeyStroke(0x26),
    'key_arrow_right' => const WindowsRemoteKeyStroke(0x27),
    'key_arrow_down' => const WindowsRemoteKeyStroke(0x28),
    'delete' => const WindowsRemoteKeyStroke(0x08),
    'enter' => const WindowsRemoteKeyStroke(0x0D),
    'key_command_a' => const WindowsRemoteKeyStroke(0x41, control),
    'key_command_c' => const WindowsRemoteKeyStroke(0x43, control),
    'key_command_v' => const WindowsRemoteKeyStroke(0x56, control),
    'key_command_x' => const WindowsRemoteKeyStroke(0x58, control),
    'key_command_z' => const WindowsRemoteKeyStroke(0x5A, control),
    // Ctrl+Y is the redo binding Windows applications agree on.
    'key_command_shift_z' => const WindowsRemoteKeyStroke(0x59, control),
    'show_desktop' || 'home' => const WindowsRemoteKeyStroke(0x44, win),
    'task_view' || 'recents' => const WindowsRemoteKeyStroke(0x09, win),
    'back' => const WindowsRemoteKeyStroke(0x25, {WindowsRemoteModifier.alt}),
    _ => _windowsKeyStrokeForChord(action),
  };
}

const _windowsKeyModifiers = <String, WindowsRemoteModifier>{
  'ctrl': WindowsRemoteModifier.control,
  'alt': WindowsRemoteModifier.alt,
  'shift': WindowsRemoteModifier.shift,
  'win': WindowsRemoteModifier.win,
};

/// Virtual-key codes of the keys a `key:` action may name. Character keys
/// are the US-layout positions.
const _windowsKeyCodes = <String, int>{
  'enter': 0x0D,
  'backspace': 0x08,
  'delete': 0x2E,
  'tab': 0x09,
  'escape': 0x1B,
  'space': 0x20,
  'left': 0x25,
  'up': 0x26,
  'right': 0x27,
  'down': 0x28,
  'home': 0x24,
  'end': 0x23,
  'pageup': 0x21,
  'pagedown': 0x22,
  'insert': 0x2D,
  'minus': 0xBD,
  'equal': 0xBB,
  'bracketleft': 0xDB,
  'bracketright': 0xDD,
  'backslash': 0xDC,
  'semicolon': 0xBA,
  'quote': 0xDE,
  'comma': 0xBC,
  'period': 0xBE,
  'slash': 0xBF,
  'backquote': 0xC0,
};

int? _windowsKeyCode(String key) {
  final named = _windowsKeyCodes[key];
  if (named != null) return named;
  if (key.length == 1) {
    final unit = key.codeUnitAt(0);
    if (unit >= 0x61 && unit <= 0x7A) return unit - 0x20; // a-z -> VK_A..VK_Z
    if (unit >= 0x30 && unit <= 0x39) return unit; // 0-9
  }
  final function = RegExp(r'^f([1-9]|1[0-2])$').firstMatch(key);
  if (function != null) return 0x70 + int.parse(function.group(1)!) - 1;
  return null;
}

/// Parses a generic key press such as `key:ctrl+shift+z`, sent by viewers
/// that forward a hardware keyboard. Null for anything not exactly in that
/// form, so a malformed request never presses a key.
WindowsRemoteKeyStroke? _windowsKeyStrokeForChord(String action) {
  const prefix = 'key:';
  if (!action.startsWith(prefix)) return null;
  final parts = action.substring(prefix.length).split('+');
  if (parts.length > 5) return null;
  final keyCode = _windowsKeyCode(parts.last);
  if (keyCode == null) return null;
  final modifiers = <WindowsRemoteModifier>{};
  for (final name in parts.take(parts.length - 1)) {
    final modifier = _windowsKeyModifiers[name];
    if (modifier == null || !modifiers.add(modifier)) return null;
  }
  return WindowsRemoteKeyStroke(keyCode, modifiers);
}
