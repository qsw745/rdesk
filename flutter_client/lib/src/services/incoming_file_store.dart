import 'dart:convert';
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
// Desktop file systems cap a name at 255 bytes; this leaves room for the
// " (n)" and ".part" suffixes added while saving.
const _maxNameBytes = 200;
const _maxExtensionBytes = 32;

final _trailingDotsAndSpaces = RegExp(r'[. ]+$');

/// The longest prefix of [text] that fits in [maxBytes] of UTF-8 without
/// cutting a character in half.
String _fitBytes(String text, int maxBytes) {
  final kept = StringBuffer();
  var used = 0;
  for (final rune in text.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
    if (used + size > maxBytes) break;
    used += size;
    kept.writeCharCode(rune);
  }
  return kept.toString();
}

/// The name an incoming file is saved under. The sender chooses the name, so
/// it is reduced to its last path component and to characters every desktop
/// file system accepts: a name can never place a file outside the folder it
/// is received into, nor be one Windows treats as a device.
String sanitizeIncomingFileName(String raw) {
  var name = raw.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '');
  name = name.replaceAll(_trailingDotsAndSpaces, '').trim();
  if (name.isEmpty) return '未命名文件';
  // Windows goes by what precedes the first dot: NUL.tar.gz is still NUL.
  final device = name.split('.').first.trim().toUpperCase();
  if (_windowsReservedNames.contains(device)) name = '_$name';

  final dot = name.lastIndexOf('.');
  var stem = dot > 0 ? name.substring(0, dot) : name;
  var extension = dot > 0 ? name.substring(dot) : '';
  if (utf8.encode(extension).length > _maxExtensionBytes) {
    stem = name;
    extension = '';
  }
  stem = _fitBytes(stem, _maxNameBytes - utf8.encode(extension).length)
      .replaceAll(_trailingDotsAndSpaces, '');
  if (stem.isEmpty) stem = '未命名文件';
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

  /// Creates a file nobody else has, adding " (n)" when the name is taken.
  /// `exclusive` makes the name check and the creation one step.
  Future<(File, String)> _createUnused(
      Directory directory, String stem, String extension) async {
    for (var attempt = 0;; attempt++) {
      final name = attempt == 0 ? '$stem$extension' : '$stem ($attempt)$extension';
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      try {
        await file.create(exclusive: true);
        return (file, name);
      } on FileSystemException {
        if (attempt >= 999 || !await file.exists()) rethrow;
      }
    }
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

    // Received under a temporary name: a transfer cut short by a crash or a
    // power cut must not look like a finished file.
    final (part, _) = await _createUnused(directory, name, '.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      // addStream waits for the disk, so a fast sender cannot pile the file
      // up in memory.
      await sink.addStream(data.map((chunk) {
        received += chunk.length;
        if (received > maxBytes) throw IncomingFileTooLarge(maxBytes);
        return chunk;
      }));
      await sink.close();
      final (file, finalName) = await _createUnused(directory, stem, extension);
      try {
        await part.rename(file.path);
      } catch (_) {
        await file.delete();
        rethrow;
      }
      return SavedIncomingFile(file, finalName);
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }
}
