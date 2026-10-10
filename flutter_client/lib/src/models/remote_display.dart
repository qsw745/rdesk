/// One screen of the computer being viewed, as the viewer presents it.
class RemoteDisplay {
  const RemoteDisplay({
    required this.index,
    required this.title,
    this.model,
    this.width,
    this.height,
    this.isMain = false,
    this.isSelected = false,
  });

  /// Shown until the other computer has said which screens it has.
  static const fallback = RemoteDisplay(index: 0, title: '主显示器', isMain: true);

  /// The position the host switches to with `switch_monitor_<index>`.
  final int index;

  /// "显示屏 1", "显示屏 2": the same for every host, so tabs line up.
  final String title;

  /// What the screen calls itself, such as "VG27AQL3A". Older hosts do not
  /// report one.
  final String? model;
  final int? width;
  final int? height;
  final bool isMain;

  /// The screen the host is showing right now. The host keeps its selection
  /// between viewers, so a new viewer may start on a screen other than the
  /// first. Older hosts do not say.
  final bool isSelected;

  String? get resolution =>
      width == null || height == null ? null : '$width×$height';

  /// The model when known, otherwise the resolution: what tells two screens
  /// apart at a glance.
  String? get detail => model ?? resolution;

  /// One line for lists and menus.
  String get label => detail == null ? title : '$title（$detail）';

  /// Everything known about the screen, for a tooltip.
  String get description => [
        if (isMain) '主显示器',
        if (model != null) model!,
        if (resolution != null) resolution!,
      ].join(' · ');

  /// Reads the host's display list. Hosts differ in what they report, and the
  /// list crosses the network, so every field is optional and anything that
  /// is not a display is skipped rather than trusted.
  static List<RemoteDisplay> parseList(Object? json) {
    if (json is! List) return const [];
    final displays = <RemoteDisplay>[];
    for (final item in json) {
      if (item is! Map) continue;
      final position = displays.length;
      final index = item['index'];
      final model = item['model'];
      final width = item['width'];
      final height = item['height'];
      final trimmedModel = model is String ? model.trim() : '';
      displays.add(RemoteDisplay(
        index: index is int && index >= 0 ? index : position,
        title: '显示屏 ${position + 1}',
        model: trimmedModel.isEmpty ? null : trimmedModel,
        width: width is int && width > 0 ? width : null,
        height: height is int && height > 0 ? height : null,
        isMain: item['isMain'] == true,
        isSelected: item['selected'] == true,
      ));
    }
    return List.unmodifiable(displays);
  }
}
