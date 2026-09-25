import 'dart:io';

/// Path access control for remote file browsing.
///
/// Everything in this file runs on the **host** (被控端). The viewer only ever
/// sends a requested path; the host decides whether that path may be listed.
/// Never rely on the viewer UI to keep requests in bounds — a crafted request
/// bypasses it entirely.

/// Why the host refused a remote file request.
enum RemoteFileDenyReason {
  /// The host has switched remote file access off entirely.
  disabled,

  /// No directory is whitelisted, so nothing can be browsed.
  noRoots,

  /// The path resolves outside every allowed root.
  outsideRoots,

  /// The path is inside an allowed root but does not exist.
  notFound,

  /// The path is inside an allowed root but is not a directory.
  notDirectory,

  /// The path could not be interpreted (embedded NUL, etc).
  invalidPath,

  /// The directory is in bounds but could not be read (permissions, races).
  readFailed,

  /// The target is in bounds but could not be written (permissions, disk).
  writeFailed,
}

extension RemoteFileDenyReasonInfo on RemoteFileDenyReason {
  /// Stable machine-readable code sent to the viewer.
  String get code => switch (this) {
        RemoteFileDenyReason.disabled => 'file_access_disabled',
        RemoteFileDenyReason.noRoots => 'no_allowed_roots',
        RemoteFileDenyReason.outsideRoots => 'path_outside_allowed_roots',
        RemoteFileDenyReason.notFound => 'path_not_found',
        RemoteFileDenyReason.notDirectory => 'path_not_directory',
        RemoteFileDenyReason.invalidPath => 'invalid_path',
        RemoteFileDenyReason.readFailed => 'path_read_failed',
        RemoteFileDenyReason.writeFailed => 'path_write_failed',
      };

  /// User-facing message shown on the viewer.
  String get message => switch (this) {
        RemoteFileDenyReason.disabled => '被控端已关闭远程文件访问。',
        RemoteFileDenyReason.noRoots => '被控端没有配置允许远程访问的目录。',
        RemoteFileDenyReason.outsideRoots => '该路径不在被控端允许访问的目录范围内。',
        RemoteFileDenyReason.notFound => '目录不存在。',
        RemoteFileDenyReason.notDirectory => '该路径不是目录。',
        RemoteFileDenyReason.invalidPath => '路径格式无法识别。',
        RemoteFileDenyReason.readFailed => '被控端无法读取该目录，可能缺少权限。',
        RemoteFileDenyReason.writeFailed => '被控端无法写入目标目录，可能缺少权限。',
      };
}

/// Result of resolving a viewer-supplied path against the host policy.
sealed class RemoteFileResolution {
  const RemoteFileResolution();
}

/// The request maps to a concrete, in-bounds directory.
final class RemoteFileResolved extends RemoteFileResolution {
  const RemoteFileResolved(this.canonicalPath);

  final String canonicalPath;
}

/// The request asked for the virtual root; answer with the allowed roots.
final class RemoteFileRootListing extends RemoteFileResolution {
  const RemoteFileRootListing(this.roots);

  final List<String> roots;
}

/// The request was refused.
final class RemoteFileDenied extends RemoteFileResolution {
  const RemoteFileDenied(this.reason);

  final RemoteFileDenyReason reason;
}

/// Path the viewer sends to ask for "the top level I am allowed to see".
const String remoteFileRootMarker = '/';

/// Turns a viewer-supplied path into an absolute path with `.`/`..`/duplicate
/// separators removed. `..` can never climb above the root — surplus segments
/// are dropped rather than escaping.
///
/// Returns null when the input cannot be interpreted as a path.
String? normalizeRequestPath(String raw) {
  if (raw.codeUnits.contains(0)) return null;
  var value = raw.trim().replaceAll('\\', '/');
  if (value.isEmpty) return remoteFileRootMarker;

  var drive = '';
  final driveMatch = RegExp(r'^/*([A-Za-z]:)(?=/|$)').firstMatch(value);
  if (driveMatch != null) {
    drive = driveMatch.group(1)!.toUpperCase();
    value = value.substring(driveMatch.end);
  }

  final segments = <String>[];
  for (final segment in value.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }

  if (drive.isNotEmpty) {
    return segments.isEmpty ? '$drive\\' : '$drive\\${segments.join('\\')}';
  }
  return segments.isEmpty ? remoteFileRootMarker : '/${segments.join('/')}';
}

/// Whether [child] is [parent] itself or lives underneath it.
///
/// Compares whole path segments, so `/Users/qsw-backup` is *not* considered to
/// be inside `/Users/qsw`. Windows drive paths compare case-insensitively.
bool isPathWithin(String parent, String child) {
  final parentParts = _splitPath(parent);
  final childParts = _splitPath(child);
  if (parentParts.root != childParts.root) return false;
  if (childParts.segments.length < parentParts.segments.length) return false;

  final ignoreCase = parentParts.root != '/';
  for (var i = 0; i < parentParts.segments.length; i++) {
    final a = parentParts.segments[i];
    final b = childParts.segments[i];
    final same = ignoreCase ? a.toLowerCase() == b.toLowerCase() : a == b;
    if (!same) return false;
  }
  return true;
}

class _SplitPath {
  const _SplitPath(this.root, this.segments);

  final String root;
  final List<String> segments;
}

_SplitPath _splitPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final driveMatch = RegExp(r'^([A-Za-z]:)(?=/|$)').firstMatch(normalized);
  final root = driveMatch != null ? driveMatch.group(1)!.toUpperCase() : '/';
  final rest =
      driveMatch != null ? normalized.substring(driveMatch.end) : normalized;
  final segments =
      rest.split('/').where((segment) => segment.isNotEmpty).toList();
  return _SplitPath(root, segments);
}

/// Host-side rule set describing which directories a viewer may browse.
class RemoteFileAccessPolicy {
  const RemoteFileAccessPolicy({
    required this.enabled,
    required this.allowedRoots,
  });

  final bool enabled;
  final List<String> allowedRoots;

  /// Allowed roots exactly as configured, normalized but not resolved.
  ///
  /// Used only to let a request through the cheap pre-check when it is spelled
  /// the same way the user spelled the root (`/tmp/x` while the root resolves
  /// to `/private/tmp/x`). The authoritative check always runs on the
  /// symlink-resolved path.
  List<String> declaredRoots() {
    final declared = <String>[];
    for (final root in allowedRoots) {
      final normalized = normalizeRequestPath(root);
      if (normalized == null || normalized == remoteFileRootMarker) continue;
      if (!declared.contains(normalized)) declared.add(normalized);
    }
    return declared;
  }

  /// Allowed roots with symlinks resolved, skipping entries that do not exist.
  ///
  /// Resolving up front means a root that is itself a symlink (a very common
  /// setup on macOS and inside containers) still matches the canonical paths we
  /// compare against later.
  Future<List<String>> canonicalRoots() async {
    final resolved = <String>[];
    for (final root in allowedRoots) {
      final normalized = normalizeRequestPath(root);
      if (normalized == null || normalized.trim().isEmpty) continue;
      final canonical = await _canonicalizeDirectory(normalized);
      if (canonical == null) continue;
      if (!resolved.contains(canonical)) resolved.add(canonical);
    }
    return resolved;
  }

  /// Resolves a viewer-supplied path, refusing anything out of bounds.
  Future<RemoteFileResolution> resolveDirectory(String requestedPath) async {
    if (!enabled) {
      return const RemoteFileDenied(RemoteFileDenyReason.disabled);
    }
    final roots = await canonicalRoots();
    if (roots.isEmpty) {
      return const RemoteFileDenied(RemoteFileDenyReason.noRoots);
    }

    final normalized = normalizeRequestPath(requestedPath);
    if (normalized == null) {
      return const RemoteFileDenied(RemoteFileDenyReason.invalidPath);
    }

    if (normalized == remoteFileRootMarker) {
      // A single root behaves like the viewer's "home": open it directly.
      if (roots.length == 1) return _resolveConcrete(roots.first, roots);
      return RemoteFileRootListing(roots);
    }
    return _resolveConcrete(normalized, roots);
  }

  /// Resolves the directory a write should land in, refusing escapes.
  ///
  /// The file itself may not exist yet, so the *parent* directory is what gets
  /// canonicalized and checked. Remote uploads (`file_receive`) must go through
  /// this before touching the filesystem.
  Future<String?> resolveWriteTarget(String absolutePath) async {
    final normalized = normalizeRequestPath(absolutePath);
    if (normalized == null || normalized == remoteFileRootMarker) return null;
    final separatorIndex = normalized.replaceAll('\\', '/').lastIndexOf('/');
    if (separatorIndex <= 0) return null;
    final parent = normalized.substring(0, separatorIndex);
    final name = normalized.substring(separatorIndex + 1);
    if (name.isEmpty) return null;

    final resolution = await resolveDirectory(parent);
    if (resolution is! RemoteFileResolved) return null;
    return '${resolution.canonicalPath}${Platform.pathSeparator}$name';
  }

  /// Cheap pre-check against both the resolved and the as-configured roots.
  ///
  /// Passing this is necessary but never sufficient — every accepted path is
  /// re-checked after symlink resolution.
  bool _lexicallyInBounds(String candidate, List<String> canonical) {
    if (canonical.any((root) => isPathWithin(root, candidate))) return true;
    return declaredRoots().any((root) => isPathWithin(root, candidate));
  }

  Future<RemoteFileResolution> _resolveConcrete(
    String candidate,
    List<String> roots,
  ) async {
    // Lexical check first: an out-of-bounds path is refused without ever
    // touching the filesystem, so denials leak nothing about what exists.
    if (!_lexicallyInBounds(candidate, roots)) {
      return const RemoteFileDenied(RemoteFileDenyReason.outsideRoots);
    }

    final directory = Directory(candidate);
    if (!await directory.exists()) {
      final isFile = await File(candidate).exists();
      return RemoteFileDenied(isFile
          ? RemoteFileDenyReason.notDirectory
          : RemoteFileDenyReason.notFound);
    }

    // Second check against the symlink-resolved path: this is what stops a
    // symlink (or a mount point reached through one) from escaping the root.
    final canonical = await _canonicalizeDirectory(candidate);
    if (canonical == null) {
      return const RemoteFileDenied(RemoteFileDenyReason.notFound);
    }
    if (!roots.any((root) => isPathWithin(root, canonical))) {
      return const RemoteFileDenied(RemoteFileDenyReason.outsideRoots);
    }
    return RemoteFileResolved(canonical);
  }
}

Future<String?> _canonicalizeDirectory(String path) async {
  try {
    final directory = Directory(path);
    if (!await directory.exists()) return null;
    return await directory.resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _canonicalizeAny(String path) async {
  try {
    if (!await FileSystemEntity.isLink(path) &&
        !await File(path).exists() &&
        !await Directory(path).exists()) {
      return null;
    }
    return await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

/// Outcome of one remote file operation, in the shape the host UI displays and
/// the relay hands back to the viewer.
abstract interface class RemoteFileOutcome {
  /// Whether the operation was carried out.
  bool get allowed;

  /// The raw path the viewer asked for (for host-side activity display).
  String get requestedPath;

  /// Canonical path that was actually used, when allowed.
  String? get resolvedPath;

  /// Why the request was refused, when denied.
  RemoteFileDenyReason? get reason;

  /// JSON-ready body handed back to the viewer through the relay.
  Map<String, Object?> get payload;
}

/// Outcome of serving one remote listing request.
class RemoteFileListResult implements RemoteFileOutcome {
  const RemoteFileListResult({
    required this.allowed,
    required this.requestedPath,
    required this.payload,
    this.resolvedPath,
    this.reason,
  });

  @override
  final bool allowed;

  @override
  final String requestedPath;

  @override
  final Map<String, Object?> payload;

  @override
  final String? resolvedPath;

  @override
  final RemoteFileDenyReason? reason;
}

/// Outcome of resolving (and optionally performing) one remote file write.
class RemoteFileWriteResult implements RemoteFileOutcome {
  const RemoteFileWriteResult({
    required this.allowed,
    required this.requestedPath,
    required this.payload,
    this.resolvedPath,
    this.reason,
  });

  @override
  final bool allowed;

  @override
  final String requestedPath;

  @override
  final Map<String, Object?> payload;

  @override
  final String? resolvedPath;

  @override
  final RemoteFileDenyReason? reason;
}

/// Serves directory listings for remote viewers under a [RemoteFileAccessPolicy].
class RemoteFileBrowser {
  const RemoteFileBrowser(this.policy, {this.maxEntries = 2000});

  final RemoteFileAccessPolicy policy;

  /// Upper bound on entries per response, so a huge directory cannot stall the
  /// relay's 5s command timeout.
  final int maxEntries;

  Future<RemoteFileListResult> list(String requestedPath) async {
    final resolution = await policy.resolveDirectory(requestedPath);
    return switch (resolution) {
      RemoteFileDenied(:final reason) => _denied(requestedPath, reason),
      RemoteFileRootListing(:final roots) => RemoteFileListResult(
          allowed: true,
          requestedPath: requestedPath,
          resolvedPath: remoteFileRootMarker,
          payload: <String, Object?>{
            'ok': true,
            'path': remoteFileRootMarker,
            'root_listing': true,
            'truncated': false,
            'entries': await _rootEntries(roots),
          },
        ),
      RemoteFileResolved(:final canonicalPath) =>
        await _listDirectory(requestedPath, canonicalPath),
    };
  }

  RemoteFileListResult _denied(
    String requestedPath,
    RemoteFileDenyReason reason,
  ) =>
      RemoteFileListResult(
        allowed: false,
        requestedPath: requestedPath,
        reason: reason,
        payload: <String, Object?>{
          'ok': false,
          'error': reason.code,
          'message': reason.message,
        },
      );

  Future<List<Map<String, Object?>>> _rootEntries(List<String> roots) async {
    final entries = <Map<String, Object?>>[];
    for (final root in roots) {
      // Roots are shown with their full path as the name: the viewer joins it
      // onto the current path, which normalizes straight back to the root.
      entries.add(<String, Object?>{
        'name': root,
        'isDir': true,
        'size': 0,
        'modified': await _modifiedMs(root),
      });
    }
    return entries;
  }

  Future<RemoteFileListResult> _listDirectory(
    String requestedPath,
    String canonicalPath,
  ) async {
    final entries = <Map<String, Object?>>[];
    var truncated = false;
    final roots = await policy.canonicalRoots();

    final List<FileSystemEntity> children;
    try {
      children =
          await Directory(canonicalPath).list(followLinks: false).toList();
    } on FileSystemException {
      return _denied(requestedPath, RemoteFileDenyReason.readFailed);
    }
    for (final entity in children) {
      if (entries.length >= maxEntries) {
        truncated = true;
        break;
      }
      try {
        // A symlink pointing out of bounds is hidden rather than listed, so it
        // can never be used as a stepping stone out of the allowed roots.
        if (entity is Link) {
          final target = await _canonicalizeAny(entity.path);
          if (target == null ||
              !roots.any((root) => isPathWithin(root, target))) {
            continue;
          }
        }
        final stat = await entity.stat();
        entries.add(<String, Object?>{
          'name': _basename(entity.path),
          'isDir': stat.type == FileSystemEntityType.directory,
          'size': stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
      } on FileSystemException {
        // Skip entries we cannot stat (permissions, races).
        continue;
      }
    }

    entries.sort((a, b) {
      final aDir = a['isDir'] == true;
      final bDir = b['isDir'] == true;
      if (aDir != bDir) return aDir ? -1 : 1;
      return (a['name'] as String)
          .toLowerCase()
          .compareTo((b['name'] as String).toLowerCase());
    });

    return RemoteFileListResult(
      allowed: true,
      requestedPath: requestedPath,
      resolvedPath: canonicalPath,
      payload: <String, Object?>{
        'ok': true,
        'path': canonicalPath,
        'root_listing': false,
        'truncated': truncated,
        'entries': entries,
      },
    );
  }

  Future<int> _modifiedMs(String path) async {
    try {
      final stat = await FileStat.stat(path);
      return stat.modified.millisecondsSinceEpoch;
    } on FileSystemException {
      return 0;
    }
  }
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/') && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  if (index < 0) return trimmed;
  final name = trimmed.substring(index + 1);
  return name.isEmpty ? trimmed : name;
}

/// Reduces a viewer-supplied file name to a single, separator-free segment.
///
/// `../../etc/passwd` becomes `passwd`, so a name can never contribute to the
/// directory part of the destination. Returns null when nothing usable is left.
String? sanitizeRemoteFileName(String raw) {
  if (raw.codeUnits.contains(0)) return null;
  final segments = raw
      .replaceAll('\\', '/')
      .split('/')
      .map((segment) => segment.trim())
      .where(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..')
      .toList();
  if (segments.isEmpty) return null;
  return segments.last;
}

/// Writes files pushed by a remote viewer, under a [RemoteFileAccessPolicy].
///
/// Runs on the host. The viewer's `remote_path` is a request, not a
/// destination: it is only honoured after the same root check the browser uses.
class RemoteFileWriter {
  const RemoteFileWriter(this.policy);

  final RemoteFileAccessPolicy policy;

  /// Resolves where an incoming file may land, without writing anything.
  Future<RemoteFileWriteResult> resolveTarget({
    required String remotePath,
    required String filename,
  }) async {
    final normalized = normalizeRequestPath(remotePath);
    if (normalized == null) {
      return _denied(remotePath, RemoteFileDenyReason.invalidPath);
    }

    // The viewer may address either the destination directory or the full
    // destination file path; try the directory reading first.
    final asDirectory = await policy.resolveDirectory(normalized);
    switch (asDirectory) {
      case RemoteFileResolved(:final canonicalPath):
        final name = sanitizeRemoteFileName(filename);
        if (name == null) {
          return _denied(remotePath, RemoteFileDenyReason.invalidPath);
        }
        return _resolved(remotePath, canonicalPath, name);
      case RemoteFileRootListing():
        // The virtual root is not a real directory — nothing can land there.
        return _denied(remotePath, RemoteFileDenyReason.outsideRoots);
      case RemoteFileDenied(:final reason):
        if (reason != RemoteFileDenyReason.notFound &&
            reason != RemoteFileDenyReason.notDirectory) {
          return _denied(remotePath, reason);
        }
    }

    // Full file path: the parent directory is what has to be in bounds, since
    // the file itself does not exist yet.
    final separatorIndex = normalized.replaceAll('\\', '/').lastIndexOf('/');
    if (separatorIndex <= 0) {
      return _denied(remotePath, RemoteFileDenyReason.outsideRoots);
    }
    final parentPath = normalized.substring(0, separatorIndex);
    final leaf =
        sanitizeRemoteFileName(normalized.substring(separatorIndex + 1));
    if (leaf == null) {
      return _denied(remotePath, RemoteFileDenyReason.invalidPath);
    }

    final parent = await policy.resolveDirectory(parentPath);
    return switch (parent) {
      RemoteFileResolved(:final canonicalPath) =>
        await _resolved(remotePath, canonicalPath, leaf),
      RemoteFileDenied(:final reason) => _denied(remotePath, reason),
      RemoteFileRootListing() =>
        _denied(remotePath, RemoteFileDenyReason.outsideRoots),
    };
  }

  /// Resolves the destination and writes [bytes] there.
  ///
  /// Never overwrites: a taken name gets a ` (n)` suffix.
  Future<RemoteFileWriteResult> write({
    required String remotePath,
    required String filename,
    required List<int> bytes,
  }) async {
    final target = await resolveTarget(
      remotePath: remotePath,
      filename: filename,
    );
    final destination = target.resolvedPath;
    if (!target.allowed || destination == null) return target;

    try {
      final path = await availablePath(destination);
      await File(path).writeAsBytes(bytes, flush: true);
      return RemoteFileWriteResult(
        allowed: true,
        requestedPath: remotePath,
        resolvedPath: path,
        payload: <String, Object?>{
          'ok': true,
          'path': path,
          'bytes': bytes.length,
        },
      );
    } on FileSystemException {
      return _denied(remotePath, RemoteFileDenyReason.writeFailed);
    }
  }

  /// Picks a free path next to [target] so an upload never clobbers an existing
  /// file: `report.pdf` becomes `report (1).pdf`.
  static Future<String> availablePath(String target) async {
    if (!await _pathExists(target)) return target;

    final separatorIndex = target.replaceAll('\\', '/').lastIndexOf('/');
    final directory = target.substring(0, separatorIndex);
    final name = target.substring(separatorIndex + 1);
    final separator = target[separatorIndex];
    final dotIndex = name.lastIndexOf('.');
    final stem = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final extension = dotIndex > 0 ? name.substring(dotIndex) : '';

    for (var i = 1; i <= 999; i++) {
      final candidate = '$directory$separator$stem ($i)$extension';
      if (!await _pathExists(candidate)) return candidate;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$directory$separator$stem ($stamp)$extension';
  }

  /// Final containment check on the composed destination, then the result.
  Future<RemoteFileWriteResult> _resolved(
    String requestedPath,
    String canonicalDirectory,
    String name,
  ) async {
    final target = '$canonicalDirectory${Platform.pathSeparator}$name';
    final roots = await policy.canonicalRoots();
    if (!roots.any((root) => isPathWithin(root, target))) {
      return _denied(requestedPath, RemoteFileDenyReason.outsideRoots);
    }
    return RemoteFileWriteResult(
      allowed: true,
      requestedPath: requestedPath,
      resolvedPath: target,
      payload: <String, Object?>{'ok': true, 'path': target},
    );
  }

  RemoteFileWriteResult _denied(
    String requestedPath,
    RemoteFileDenyReason reason,
  ) =>
      RemoteFileWriteResult(
        allowed: false,
        requestedPath: requestedPath,
        reason: reason,
        payload: <String, Object?>{
          'ok': false,
          'error': reason.code,
          'message': reason.message,
        },
      );
}

Future<bool> _pathExists(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  return type != FileSystemEntityType.notFound;
}
