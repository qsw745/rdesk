/// What a Mac modifier key becomes on a Windows computer being controlled.
enum RemoteModifier {
  win('Win'),
  ctrl('Ctrl'),
  alt('Alt');

  const RemoteModifier(this.label);
  final String label;
}

/// What a Mac delete key becomes on a Windows computer being controlled.
enum DeleteKeyTarget {
  backspace('Backspace'),
  delete('Delete');

  const DeleteKeyTarget(this.label);
  final String label;
}

/// How a Mac keyboard is translated when the remote computer runs Windows.
class WindowsKeyMapping {
  const WindowsKeyMapping({
    this.command = RemoteModifier.win,
    this.option = RemoteModifier.alt,
    this.control = RemoteModifier.ctrl,
    this.delete = DeleteKeyTarget.backspace,
    this.fnDelete = DeleteKeyTarget.delete,
  });

  static const defaults = WindowsKeyMapping();

  final RemoteModifier command;
  final RemoteModifier option;
  final RemoteModifier control;

  /// The key labelled "delete" on a Mac keyboard.
  final DeleteKeyTarget delete;

  /// Fn + delete on a Mac keyboard, or the forward-delete key.
  final DeleteKeyTarget fnDelete;

  WindowsKeyMapping copyWith({
    RemoteModifier? command,
    RemoteModifier? option,
    RemoteModifier? control,
    DeleteKeyTarget? delete,
    DeleteKeyTarget? fnDelete,
  }) =>
      WindowsKeyMapping(
        command: command ?? this.command,
        option: option ?? this.option,
        control: control ?? this.control,
        delete: delete ?? this.delete,
        fnDelete: fnDelete ?? this.fnDelete,
      );

  Map<String, String> toJson() => {
        'command': command.name,
        'option': option.name,
        'control': control.name,
        'delete': delete.name,
        'fnDelete': fnDelete.name,
      };

  /// Anything missing or unrecognised falls back to its default.
  factory WindowsKeyMapping.fromJson(Object? json) {
    if (json is! Map) return defaults;
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final name = json[key];
      return values.firstWhere((v) => v.name == name, orElse: () => fallback);
    }

    return WindowsKeyMapping(
      command: pick(RemoteModifier.values, 'command', defaults.command),
      option: pick(RemoteModifier.values, 'option', defaults.option),
      control: pick(RemoteModifier.values, 'control', defaults.control),
      delete: pick(DeleteKeyTarget.values, 'delete', defaults.delete),
      fnDelete: pick(DeleteKeyTarget.values, 'fnDelete', defaults.fnDelete),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WindowsKeyMapping &&
      other.command == command &&
      other.option == option &&
      other.control == control &&
      other.delete == delete &&
      other.fnDelete == fnDelete;

  @override
  int get hashCode => Object.hash(command, option, control, delete, fnDelete);
}
