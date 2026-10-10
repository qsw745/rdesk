import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Thrown when an incoming file exceeds the size the receiver accepts.
class IncomingFileTooLarge implements Exception {
  const IncomingFileTooLarge(this.maxBytes);
  final int maxBytes;
}

class SavedIncomingFile {
  const SavedIncomingFile(this.file, this.name);
  final File file;
  final String name;
}

const _windowsReservedNames = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};
const _maxNameLength = 120;

/// The name an incoming file is saved under. The sender chooses the name, so
/// it is reduced to its last path component and to characters every desktop
/// file system accepts: a name can never place a file outside the folder it
/// is received into, nor be one Windows treats as a device.
String sanitizeIncomingFileName(String raw) {
  var name = raw.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '');
  name = name.replaceAll(RegExp(r'[. ]+$'), '').trim();
  if (name.isEmpty) return '未命名文件';
  final dot = name.lastIndexOf('.');
  var stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  if (_windowsReservedNames.contains(stem.toUpperCase())) stem = '_$stem';
  final room = _maxNameLength - extension.length;
  if (room > 0 && stem.length > room) stem = stem.substring(0, room);
  return '$stem$extension';
}

/// Where files sent by a remote viewer end up: this computer's Downloads
/// folder. Existing files are never overwritten.
class IncomingFileStore {
  const IncomingFileStore({Future<Directory> Function()? directory})
      : _directory = directory;

  final Future<Directory> Function()? _directory;

  Future<Directory> _resolve() async {
    final custom = _directory;
    if (custom != null) return custom();
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return Directory('$home${Platform.pathSeparator}Downloads');
  }

  /// Writes [data] under a safe, unused name. Stops and removes the partial
  /// file if more than [maxBytes] arrive or the transfer breaks.
  Future<SavedIncomingFile> save(String rawName, Stream<List<int>> data,
      {required int maxBytes}) async {
    final directory = await _resolve();
    await directory.create(recursive: true);
    final name = sanitizeIncomingFileName(rawName);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';

    // `exclusive` makes the name check and the creation one step.
    late File file;
    late String finalName;
    for (var attempt = 0;; attempt++) {
      finalName = attempt == 0 ? name : '$stem ($attempt)$extension';
      file = File('${directory.path}${Platform.pathSeparator}$finalName');
      try {
        await file.create(exclusive: true);
        break;
      } on FileSystemException {
        if (attempt >= 999 || !await file.exists()) rethrow;
      }
    }

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in data) {
        received += chunk.length;
        if (received > maxBytes) throw IncomingFileTooLarge(maxBytes);
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return SavedIncomingFile(file, finalName);
  }
}
