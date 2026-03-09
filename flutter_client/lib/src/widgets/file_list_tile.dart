import 'package:flutter/material.dart';

import '../models/file_entry.dart';

class FileListTileWidget extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;

  const FileListTileWidget({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _resolveIcon(entry);
    final label = _resolveLabel(entry);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon),
      ),
      title: Text(entry.name),
      subtitle: Text(
        entry.isDir
            ? '文件夹 • ${entry.modified.toLocal()}'
            : '$label • ${entry.sizeDisplay} • ${entry.modified.toLocal()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.isDir ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }

  IconData _resolveIcon(FileEntry entry) {
    if (entry.isDir) return Icons.folder_outlined;
    final name = entry.name.toLowerCase();
    if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.mkv')) {
      return Icons.movie_outlined;
    }
    if (name.endsWith('.zip') || name.endsWith('.rar') || name.endsWith('.7z')) {
      return Icons.archive_outlined;
    }
    if (name.endsWith('.pdf') || name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _resolveLabel(FileEntry entry) {
    if (entry.isDir) return '文件夹';
    final name = entry.name.toLowerCase();
    if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return '图片';
    }
    if (name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.mkv')) {
      return '视频';
    }
    if (name.endsWith('.zip') || name.endsWith('.rar') || name.endsWith('.7z')) {
      return '压缩包';
    }
    if (name.endsWith('.pdf') || name.endsWith('.doc') || name.endsWith('.docx')) {
      return '文档';
    }
    return '文件';
  }
}
