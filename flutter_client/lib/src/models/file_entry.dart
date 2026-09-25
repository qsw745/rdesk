class FileEntry {
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;

  const FileEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  String get sizeDisplay {
    if (isDir) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class TransferProgress {
  final int id;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final bool isUpload;
  final TransferState state;

  const TransferProgress({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.isUpload,
    required this.state,
  });

  double get progress =>
      totalBytes > 0 ? transferredBytes / totalBytes : 0.0;
}

enum TransferState {
  pending,
  transferring,
  completed,
  failed,
  cancelled,
}
