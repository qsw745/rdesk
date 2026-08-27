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
