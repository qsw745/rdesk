import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../models/file_entry.dart';
import '../services/rdesk_bridge_service.dart';

/// Path the viewer sends to ask the host for "the top of what I may browse".
const String remoteRootRequestPath = '/';

class FileTransferProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  List<FileEntry> _localFiles = [];
  List<FileEntry> _remoteFiles = [];
  String _localPath = RdeskBridgeService.instance.defaultBrowserPath;
  String _remotePath = '/';
  final List<TransferProgress> _transfers = [];
  final Map<int, Timer> _progressTimers = {};
  final Set<String> _selectedLocalFiles = {};
  final Set<String> _selectedRemoteFiles = {};
  bool _isSelectionMode = false;
  String? _remoteError;
  String? _remoteErrorCode;
  bool _remoteIsRootListing = false;
  String? _remoteRootPath;
  String? _uploadError;
  bool _uploadErrorIsDenial = false;

  List<FileEntry> get localFiles => _localFiles;
  List<FileEntry> get remoteFiles => _remoteFiles;
  String get localPath => _localPath;
  String get remotePath => _remotePath;
  List<TransferProgress> get transfers => List.unmodifiable(_transfers);
  String get defaultLocalPath => _bridge.defaultBrowserPath;
  Set<String> get selectedLocalFiles => Set.unmodifiable(_selectedLocalFiles);
  Set<String> get selectedRemoteFiles => Set.unmodifiable(_selectedRemoteFiles);
  bool get isSelectionMode => _isSelectionMode;
  bool get hasSelection =>
      _selectedLocalFiles.isNotEmpty || _selectedRemoteFiles.isNotEmpty;
  String? get remoteError => _remoteError;

  /// Machine-readable reason from the host when it refused the path.
  String? get remoteErrorCode => _remoteErrorCode;

  /// True when the host refused the path rather than failing to reach it.
  bool get remoteAccessDenied => _remoteErrorCode != null;

  /// True when the remote pane is showing the host's allowed roots rather than
  /// a directory's contents.
  bool get remoteIsRootListing => _remoteIsRootListing;

  /// Directory the host opened for the virtual root, when it has a single
  /// allowed root. Used to keep the breadcrumb inside the allowed range.
  String? get remoteRootPath => _remoteRootPath;

  /// Reason the most recent upload did not go through, until acknowledged.
  String? get uploadError => _uploadError;

  /// True when the last upload failed because the host refused the destination.
  bool get uploadErrorIsDenial => _uploadErrorIsDenial;

  Future<void> loadLocalDir(String path) async {
    _localPath = path;
    _localFiles = await _bridge.listLocalDirectory(path);
    _selectedLocalFiles.clear();
    notifyListeners();
  }

  Future<void> loadRemoteDir(String sessionId, String path) async {
    try {
      final listing = await _bridge.listRemoteDirectory(sessionId, path);
      _remoteFiles = listing.entries;
      // Only move the browser once the host actually served the directory, so a
      // refused path leaves the user where they were. The host reports the path
      // it resolved to, which is what subsequent navigation must build on.
      _remotePath = listing.path;
      _remoteIsRootListing = listing.isRootListing;
      if (path == remoteRootRequestPath && !listing.isRootListing) {
        _remoteRootPath = listing.path;
      }
      _remoteError = null;
      _remoteErrorCode = null;
    } on RemoteDirectoryException catch (e) {
      _remoteFiles = [];
      _remoteError = e.message;
      _remoteErrorCode = e.code;
    } catch (e) {
      _remoteFiles = [];
      _remoteError = e.toString().replaceFirst('Exception: ', '');
      _remoteErrorCode = null;
    }
    _selectedRemoteFiles.clear();
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedLocalFiles.clear();
      _selectedRemoteFiles.clear();
    }
    notifyListeners();
  }

  void toggleLocalSelection(String name) {
    if (_selectedLocalFiles.contains(name)) {
      _selectedLocalFiles.remove(name);
    } else {
      _selectedLocalFiles.add(name);
    }
    notifyListeners();
  }

  void toggleRemoteSelection(String name) {
    if (_selectedRemoteFiles.contains(name)) {
      _selectedRemoteFiles.remove(name);
    } else {
      _selectedRemoteFiles.add(name);
    }
    notifyListeners();
  }

  Future<void> uploadFile(
      String sessionId, String localPath, String remotePath) async {
    final fileName = localPath.split(Platform.pathSeparator).last;
    final file = File(localPath);
    final totalBytes = file.existsSync() ? file.lengthSync() : 1024 * 1024;

    final id = DateTime.now().millisecondsSinceEpoch;
    var transfer = TransferProgress(
      id: id,
      fileName: fileName,
      totalBytes: totalBytes,
      transferredBytes: 0,
      isUpload: true,
      state: TransferState.transferring,
    );
    _transfers.insert(0, transfer);
    notifyListeners();

    _simulateProgress(id, totalBytes);
    final result = await _bridge.uploadFile(sessionId, localPath, remotePath);
    if (!result.ok) {
      // The host may have refused the destination — never let that read as done.
      _progressTimers.remove(id)?.cancel();
      _markTransferFailed(id);
      _uploadError = result.message ?? '上传失败';
      _uploadErrorIsDenial = result.isDenied;
      notifyListeners();
    }
  }

  void _markTransferFailed(int id) {
    final index = _transfers.indexWhere((transfer) => transfer.id == id);
    if (index < 0) return;
    final current = _transfers[index];
    _transfers[index] = TransferProgress(
      id: current.id,
      fileName: current.fileName,
      totalBytes: current.totalBytes,
      transferredBytes: current.transferredBytes,
      isUpload: current.isUpload,
      state: TransferState.failed,
    );
  }

  /// Clears the last upload error after the UI has shown it.
  void clearUploadError() {
    if (_uploadError == null) return;
    _uploadError = null;
    _uploadErrorIsDenial = false;
    notifyListeners();
  }

  Future<void> downloadFile(
      String sessionId, String remotePath, String localPath) async {
    final fileName = remotePath.split('/').last;
    final totalBytes = 1024 * 1024; // estimate

    final id = DateTime.now().millisecondsSinceEpoch;
    var transfer = TransferProgress(
      id: id,
      fileName: fileName,
      totalBytes: totalBytes,
      transferredBytes: 0,
      isUpload: false,
      state: TransferState.transferring,
    );
    _transfers.insert(0, transfer);
    notifyListeners();

    try {
      await _bridge.downloadFile(sessionId, remotePath, localPath);
    } catch (_) {
      // Mark as failed instead of faking success.
      final idx = _transfers.indexWhere((tr) => tr.id == id);
      if (idx >= 0) {
        _transfers[idx] = TransferProgress(
          id: id,
          fileName: fileName,
          totalBytes: totalBytes,
          transferredBytes: 0,
          isUpload: false,
          state: TransferState.failed,
        );
        notifyListeners();
      }
      return;
    }
  }

  Future<void> uploadSelectedFiles(String sessionId) async {
    for (final name in _selectedLocalFiles.toList()) {
      final fullPath = '$_localPath/$name';
      await uploadFile(sessionId, fullPath, '$_remotePath/$name');
    }
    _selectedLocalFiles.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<void> downloadSelectedFiles(String sessionId) async {
    for (final name in _selectedRemoteFiles.toList()) {
      final fullPath = '$_remotePath/$name';
      await downloadFile(sessionId, fullPath, '$_localPath/$name');
    }
    _selectedRemoteFiles.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  void _simulateProgress(int id, int totalBytes) {
    final rng = Random();
    var transferred = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final idx = _transfers.indexWhere((tr) => tr.id == id);
      if (idx < 0) {
        t.cancel();
        _progressTimers.remove(id);
        return;
      }

      final chunk = (totalBytes * (0.08 + rng.nextDouble() * 0.15)).toInt();
      transferred = min(transferred + chunk, totalBytes);
      final done = transferred >= totalBytes;

      _transfers[idx] = TransferProgress(
        id: id,
        fileName: _transfers[idx].fileName,
        totalBytes: totalBytes,
        transferredBytes: transferred,
        isUpload: _transfers[idx].isUpload,
        state: done ? TransferState.completed : TransferState.transferring,
      );
      notifyListeners();

      if (done) {
        t.cancel();
        _progressTimers.remove(id);
      }
    });
    _progressTimers[id] = timer;
  }

  void cancelTransfer(int id) {
    _progressTimers[id]?.cancel();
    _progressTimers.remove(id);
    final idx = _transfers.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _transfers[idx] = TransferProgress(
        id: id,
        fileName: _transfers[idx].fileName,
        totalBytes: _transfers[idx].totalBytes,
        transferredBytes: _transfers[idx].transferredBytes,
        isUpload: _transfers[idx].isUpload,
        state: TransferState.cancelled,
      );
    }
    notifyListeners();
  }

  void clearCompletedTransfers() {
    _transfers.removeWhere((t) =>
        t.state == TransferState.completed ||
        t.state == TransferState.cancelled);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    _progressTimers.clear();
    super.dispose();
  }
}
