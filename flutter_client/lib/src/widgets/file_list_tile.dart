import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../utils/theme.dart';

class FileListTileWidget extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onUpload;
  final VoidCallback? onDownload;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelect;

  const FileListTileWidget({
    super.key,
    required this.entry,
    required this.onTap,
    this.onUpload,
    this.onDownload,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = _resolveIcon(entry);
    final iconColor = _resolveIconColor(entry, isDark);
    final iconBg = iconColor.withValues(alpha: 0.1);

    return InkWell(
      onTap: selectionMode ? onToggleSelect : onTap,
      onLongPress: onToggleSelect,
      child: Container(
        color: selected
            ? AppTheme.primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelect?.call(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!selectionMode && !entry.isDir) ...[
              if (onUpload != null)
                _ActionButton(
                  icon: Icons.cloud_upload_outlined,
                  tooltip: '上传到远端',
                  color: AppTheme.primaryBlue,
                  onTap: onUpload!,
                ),
              if (onDownload != null)
                _ActionButton(
                  icon: Icons.cloud_download_outlined,
                  tooltip: '下载到本地',
                  color: AppTheme.successGreen,
                  onTap: onDownload!,
                ),
            ],
            if (!selectionMode && entry.isDir)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    if (entry.isDir) return '文件夹';
    return '${entry.sizeDisplay}  ${_formatTime(entry.modified)}';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  IconData _resolveIcon(FileEntry entry) {
    if (entry.isDir) return Icons.folder_rounded;
    final name = entry.name.toLowerCase();
    if (_isImage(name)) return Icons.image_outlined;
    if (_isVideo(name)) return Icons.movie_outlined;
    if (_isArchive(name)) return Icons.archive_outlined;
    if (_isDoc(name)) return Icons.description_outlined;
    if (_isAudio(name)) return Icons.audiotrack_outlined;
    if (_isCode(name)) return Icons.code_outlined;
    if (name.endsWith('.apk') || name.endsWith('.ipa')) {
      return Icons.android_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _resolveIconColor(FileEntry entry, bool isDark) {
    if (entry.isDir) return const Color(0xFFFFA726);
    final name = entry.name.toLowerCase();
    if (_isImage(name)) return const Color(0xFF26C6DA);
    if (_isVideo(name)) return const Color(0xFFEF5350);
    if (_isArchive(name)) return const Color(0xFF8D6E63);
    if (_isDoc(name)) return AppTheme.primaryBlue;
    if (_isAudio(name)) return AppTheme.accentPurple;
    return isDark ? Colors.white38 : Colors.grey;
  }

  bool _isImage(String n) =>
      n.endsWith('.png') ||
      n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.gif') ||
      n.endsWith('.webp') ||
      n.endsWith('.bmp');

  bool _isVideo(String n) =>
      n.endsWith('.mp4') ||
      n.endsWith('.mov') ||
      n.endsWith('.mkv') ||
      n.endsWith('.avi') ||
      n.endsWith('.flv');

  bool _isArchive(String n) =>
      n.endsWith('.zip') ||
      n.endsWith('.rar') ||
      n.endsWith('.7z') ||
      n.endsWith('.tar') ||
      n.endsWith('.gz');

  bool _isDoc(String n) =>
      n.endsWith('.pdf') ||
      n.endsWith('.doc') ||
      n.endsWith('.docx') ||
      n.endsWith('.xls') ||
      n.endsWith('.xlsx') ||
      n.endsWith('.ppt') ||
      n.endsWith('.txt');

  bool _isAudio(String n) =>
      n.endsWith('.mp3') ||
      n.endsWith('.wav') ||
      n.endsWith('.flac') ||
      n.endsWith('.aac');

  bool _isCode(String n) =>
      n.endsWith('.dart') ||
      n.endsWith('.py') ||
      n.endsWith('.js') ||
      n.endsWith('.ts') ||
      n.endsWith('.rs') ||
      n.endsWith('.java');
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
