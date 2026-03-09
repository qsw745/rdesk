import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/file_entry.dart';
import '../services/rdesk_bridge_service.dart';

class FileTransferProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  List<FileEntry> _localFiles = [];
  List<FileEntry> _remoteFiles = [];
  String _localPath = RdeskBridgeService.instance.defaultBrowserPath;
  String _remotePath = '/';
  final List<TransferProgress> _transfers = [];

  List<FileEntry> get localFiles => _localFiles;
  List<FileEntry> get remoteFiles => _remoteFiles;
  String get localPath => _localPath;
  String get remotePath => _remotePath;
  List<TransferProgress> get transfers => List.unmodifiable(_transfers);
  String get defaultLocalPath => _bridge.defaultBrowserPath;

  Future<void> loadLocalDir(String path) async {
    _localPath = path;
    _localFiles = await _bridge.listLocalDirectory(path);
    notifyListeners();
  }

  Future<void> loadRemoteDir(String sessionId, String path) async {
    _remotePath = path;
    _remoteFiles = await _bridge.listRemoteDirectory(sessionId, path);
    notifyListeners();
  }

  Future<void> uploadFile(String sessionId, String localPath, String remotePath) async {
    final transfer = TransferProgress(
      id: DateTime.now().millisecondsSinceEpoch,
      fileName: localPath.split(Platform.pathSeparator).last,
      totalBytes: 100,
      transferredBytes: 100,
      isUpload: true,
      state: TransferState.completed,
    );
    _transfers.insert(0, transfer);
    await _bridge.uploadFile(sessionId, localPath, remotePath);
    notifyListeners();
  }

  Future<void> downloadFile(String sessionId, String remotePath, String localPath) async {
    final transfer = TransferProgress(
      id: DateTime.now().millisecondsSinceEpoch,
      fileName: remotePath.split('/').last,
      totalBytes: 100,
      transferredBytes: 100,
      isUpload: false,
      state: TransferState.completed,
    );
    _transfers.insert(0, transfer);
    await _bridge.downloadFile(sessionId, remotePath, localPath);
    notifyListeners();
  }

  void updateTransferProgress(int id, int transferred) {
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index >= 0) {
      notifyListeners();
    }
  }

  void cancelTransfer(int id) {
    _transfers.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
