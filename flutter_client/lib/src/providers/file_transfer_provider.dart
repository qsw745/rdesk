import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/file_entry.dart';
import '../services/rdesk_bridge_service.dart';

typedef FileSender = Future<FileSendResult> Function(
    String sessionId, String localPath,
    {Future<void>? cancelled});

class FileTransferProvider extends ChangeNotifier {
  FileTransferProvider({FileSender? send}) : _send = send;

  final _bridge = RdeskBridgeService.instance;

  /// Replaceable for tests; defaults to the real transfer.
  final FileSender? _send;

  /// Follows the session: a watching-only session writes nothing to the
  /// other computer, files included.
  bool viewOnly = false;
  final Map<int, Completer<void>> _uploadCancels = {};
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

  Future<void> loadLocalDir(String path) async {
    _localPath = path;
    _localFiles = await _bridge.listLocalDirectory(path);
    _selectedLocalFiles.clear();
    notifyListeners();
  }

  Future<void> loadRemoteDir(String sessionId, String path) async {
    _remotePath = path;
    try {
      _remoteFiles = await _bridge.listRemoteDirectory(sessionId, path);
      _remoteError = null;
    } catch (e) {
      _remoteFiles = [];
      _remoteError = e.toString().replaceFirst('Exception: ', '');
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

  /// Sends one file to the other computer, which saves it in its Downloads
  /// folder ([remotePath] is not honoured by desktop hosts).
  Future<FileSendResult> uploadFile(
      String sessionId, String localPath, String remotePath) async {
    if (viewOnly) return const FileSendResult(FileSendOutcome.viewOnly);
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

    // The entry shows what really happened: no made-up progress, and
    // "completed" only once the other computer confirmed the save.
    final cancel = _uploadCancels[id] = Completer<void>();
    FileSendResult result;
    try {
      result = await (_send ?? _bridge.sendFileToHost)(sessionId, localPath,
          cancelled: cancel.future);
    } on Exception catch (error) {
      debugPrint('[RDesk] file not sent: ${error.runtimeType}');
      result = const FileSendResult(FileSendOutcome.failed);
    } finally {
      _uploadCancels.remove(id);
    }
    final idx = _transfers.indexWhere((tr) => tr.id == id);
    if (idx >= 0 && _transfers[idx].state == TransferState.transferring) {
      _transfers[idx] = TransferProgress(
        id: id,
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: result.saved ? totalBytes : 0,
        isUpload: true,
        state: result.saved ? TransferState.completed : TransferState.failed,
      );
      notifyListeners();
    }
    return result;
  }

  Future<void> downloadFile(
      String sessionId, String remotePath, String localPath) async {
    final fileName = remotePath.split('/').last;
    const totalBytes = 1024 * 1024; // estimate

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

  void cancelTransfer(int id) {
    _progressTimers[id]?.cancel();
    _progressTimers.remove(id);
    final upload = _uploadCancels.remove(id);
    if (upload != null && !upload.isCompleted) upload.complete();
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
    _transfers.removeWhere(
        (t) => t.state == TransferState.completed || t.state == TransferState.cancelled);
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
