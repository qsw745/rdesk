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
    _ => null,
  };
}
