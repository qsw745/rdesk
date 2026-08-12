import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../utils/theme.dart';

/// Quality options used by both the bottom sheet and the desktop sidebar.
const qualityOptions = [
  ('auto', '自适应', '根据网络自动调节'),
  ('high', '高清', '原始分辨率，高流量'),
  ('medium', '标清', '降低分辨率，平衡体验'),
  ('low', '流畅', '最低画质，优先流畅度'),
];

/// Reusable quality settings content — embeddable in a sidebar or bottom sheet.
class QualitySettingsContent extends StatefulWidget {
  /// If true, shows a bottom sheet-style drag handle and header.
  final bool showHeader;

  /// If true, shows the "应用设置" button that pops the navigator.
  final bool showApplyButton;

  const QualitySettingsContent({
    super.key,
    this.showHeader = false,
    this.showApplyButton = false,
  });

  @override
  State<QualitySettingsContent> createState() => _QualitySettingsContentState();
}

class _QualitySettingsContentState extends State<QualitySettingsContent> {
  String _quality = 'auto';
  int _fps = 30;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    _quality = session.qualityPreset;
    _fps = session.fpsLimit;
  }

  void _apply() {
    context.read<SessionProvider>().setQualityPreset(_quality, _fps);
    if (widget.showApplyButton) {
      Navigator.pop(context);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '画质已设为 ${qualityOptions.firstWhere((o) => o.$1 == _quality).$2}，帧率 $_fps FPS'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.high_quality_outlined,
                      color: AppTheme.primaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '画质设置',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],

        // Quality options
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: qualityOptions.map((opt) {
              final selected = _quality == opt.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                      : (isDark
                          ? const Color(0xFF242A3D)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      setState(() => _quality = opt.$1);
                      _apply();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color:
                                selected ? AppTheme.primaryBlue : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(opt.$2,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.primaryBlue
                                          : null,
                                    )),
                                const SizedBox(height: 2),
                                Text(opt.$3,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : AppTheme.textMuted,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // FPS slider
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              Text('帧率',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppTheme.textMuted,
                  )),
              Expanded(
                child: Slider(
                  value: _fps.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  label: '$_fps FPS',
                  onChanged: (v) {
                    setState(() => _fps = v.round());
                    _apply();
                  },
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$_fps FPS',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (widget.showApplyButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _apply,
                child: const Text('应用设置'),
              ),
            ),
          ),
      ],
    );
  }
}
