import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../providers/file_transfer_provider.dart';
import '../providers/session_provider.dart';
import '../utils/theme.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/transfer_progress.dart';

class FileManagerScreen extends StatefulWidget {
  final String sessionId;

  const FileManagerScreen({super.key, required this.sessionId});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _disconnectHandled = false;
  static const _terminalStates = {
    '已被对端断开',
    '已离线',
    '设备离线',
    '密码已变更',
    '重连失败',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final provider = context.read<FileTransferProvider>();
    provider.loadLocalDir(provider.defaultLocalPath);
    provider.loadRemoteDir(widget.sessionId, remoteRootRequestPath);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _checkDisconnect(String label) {
    if (_disconnectHandled || !_terminalStates.contains(label)) return;
    _disconnectHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SessionProvider>().clearSession();
      context.go('/');
    });
  }

  /// Surfaces a refused or failed upload once, then clears it.
  void _reportUploadError(String? message) {
    if (message == null) return;
    final provider = context.read<FileTransferProvider>();
    final denied = provider.uploadErrorIsDenial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(denied ? '被控端拒绝了该上传：$message' : message),
          backgroundColor: denied ? AppTheme.warningAmber : AppTheme.errorRed,
        ),
      );
      provider.clearUploadError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = context.select<SessionProvider, String>(
      (p) => p.connectionStatusLabel,
    );
    _checkDisconnect(statusLabel);
    // Watch only the error field: the transfer list ticks several times a
    // second while an upload runs.
    _reportUploadError(
      context.select<FileTransferProvider, String?>((p) => p.uploadError),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/remote/${widget.sessionId}'),
        ),
        actions: [
          Consumer<FileTransferProvider>(
            builder: (context, provider, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.transfers.any((t) =>
                      t.state == TransferState.completed ||
                      t.state == TransferState.cancelled))
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_outlined,
                          size: 20),
                      tooltip: '清除已完成',
                      onPressed: provider.clearCompletedTransfers,
                    ),
                  IconButton(
                    icon: Icon(
                      provider.isSelectionMode
                          ? Icons.check_circle
                          : Icons.checklist_rounded,
                      size: 22,
                      color: provider.isSelectionMode
                          ? AppTheme.primaryBlue
                          : null,
                    ),
                    tooltip: provider.isSelectionMode ? '退出多选' : '多选模式',
                    onPressed: provider.toggleSelectionMode,
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Transfer progress bar
          Consumer<FileTransferProvider>(
            builder: (context, provider, _) {
              final active = provider.transfers
                  .where((t) => t.state == TransferState.transferring)
                  .toList();
              if (active.isEmpty && provider.transfers.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: provider.transfers.length,
                        itemBuilder: (context, index) {
                          return TransferProgressWidget(
                            transfer: provider.transfers[index],
                            onCancel: () => provider
                                .cancelTransfer(provider.transfers[index].id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Batch action bar
          Consumer<FileTransferProvider>(
            builder: (context, provider, _) {
              if (!provider.isSelectionMode || !provider.hasSelection) {
                return const SizedBox.shrink();
              }
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Text(
                      '已选择 ${provider.selectedLocalFiles.length + provider.selectedRemoteFiles.length} 项',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (provider.selectedLocalFiles.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () =>
                            provider.uploadSelectedFiles(widget.sessionId),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('上传'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    if (provider.selectedRemoteFiles.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () =>
                            provider.downloadSelectedFiles(widget.sessionId),
                        icon:
                            const Icon(Icons.cloud_download_outlined, size: 18),
                        label: const Text('下载'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.successGreen,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          // Responsive file browser
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                if (isNarrow) {
                  return _buildTabLayout();
                }
                return _buildDualPaneLayout();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabLayout() {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.phone_android), text: '本地'),
              Tab(icon: Icon(Icons.cloud_outlined), text: '远程'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FileBrowser(
                title: '本地',
                isLocal: true,
                sessionId: widget.sessionId,
              ),
              _FileBrowser(
                title: '远程',
                isLocal: false,
                sessionId: widget.sessionId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDualPaneLayout() {
    return Row(
      children: [
        Expanded(
          child: _FileBrowser(
            title: '本地',
            isLocal: true,
            sessionId: widget.sessionId,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _FileBrowser(
            title: '远程',
            isLocal: false,
            sessionId: widget.sessionId,
          ),
        ),
      ],
    );
  }
}

/// Shown in the remote pane when the host refused or could not serve a path.
class _RemoteErrorNotice extends StatelessWidget {
  final String message;
  final bool denied;
  final VoidCallback onRetry;

  const _RemoteErrorNotice({
    required this.message,
    required this.denied,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final color = denied ? AppTheme.warningAmber : AppTheme.errorRed;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
              size: 44,
              color: color,
            ),
            const SizedBox(height: 12),
            Text(
              denied ? '被控端拒绝访问' : '无法读取远程目录',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            if (denied) ...[
              const SizedBox(height: 6),
              Text(
                '可访问范围由被控端在「设置 → 远程文件访问」中决定。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileBrowser extends StatelessWidget {
  final String title;
  final bool isLocal;
  final String sessionId;

  const _FileBrowser({
    required this.title,
    required this.isLocal,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Consumer<FileTransferProvider>(
          builder: (context, provider, _) {
            final path = isLocal ? provider.localPath : provider.remotePath;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isLocal ? Icons.phone_android : Icons.cloud_outlined,
                        size: 16,
                        color: isLocal
                            ? AppTheme.primaryBlue
                            : AppTheme.accentPurple,
                      ),
                      const SizedBox(width: 6),
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () {
                          if (isLocal) {
                            provider.loadLocalDir(provider.localPath);
                          } else {
                            provider.loadRemoteDir(
                                sessionId, provider.remotePath);
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            _buildBreadcrumbChips(context, path, provider),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // File list
        Expanded(
          child: Consumer<FileTransferProvider>(
            builder: (context, provider, _) {
              final files =
                  isLocal ? provider.localFiles : provider.remoteFiles;
              if (!isLocal && provider.remoteError != null) {
                return _RemoteErrorNotice(
                  message: provider.remoteError!,
                  denied: provider.remoteAccessDenied,
                  onRetry: () =>
                      provider.loadRemoteDir(sessionId, provider.remotePath),
                );
              }
              if (files.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('目录为空',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }
              final selected = isLocal
                  ? provider.selectedLocalFiles
                  : provider.selectedRemoteFiles;
              return ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 66),
                itemBuilder: (context, index) {
                  final entry = files[index];
                  return FileListTileWidget(
                    entry: entry,
                    selectionMode: provider.isSelectionMode,
                    selected: selected.contains(entry.name),
                    onToggleSelect: () {
                      if (isLocal) {
                        provider.toggleLocalSelection(entry.name);
                      } else {
                        provider.toggleRemoteSelection(entry.name);
                      }
                    },
                    onTap: () {
                      if (entry.isDir) {
                        final currentPath =
                            isLocal ? provider.localPath : provider.remotePath;
                        final newPath = '$currentPath/${entry.name}';
                        if (isLocal) {
                          provider.loadLocalDir(newPath);
                        } else {
                          provider.loadRemoteDir(sessionId, newPath);
                        }
                      }
                    },
                    onUpload: isLocal && !entry.isDir
                        ? () {
                            provider.uploadFile(
                              sessionId,
                              '${provider.localPath}/${entry.name}',
                              '${provider.remotePath}/${entry.name}',
                            );
                          }
                        : null,
                    onDownload: !isLocal && !entry.isDir
                        ? () {
                            provider.downloadFile(
                              sessionId,
                              '${provider.remotePath}/${entry.name}',
                              '${provider.localPath}/${entry.name}',
                            );
                          }
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBreadcrumbChips(
    BuildContext context,
    String path,
    FileTransferProvider provider,
  ) {
    final normalized = path.replaceAll('\\', '/');

    // On the remote side the crumbs start at the host's allowed root: anything
    // above it would be refused, so it is not offered as a destination.
    final remoteRoot = isLocal ? null : provider.remoteRootPath;
    final base = remoteRoot != null && normalized.startsWith(remoteRoot)
        ? remoteRoot
        : '';
    final parts = normalized
        .substring(base.length)
        .split('/')
        .where((item) => item.isNotEmpty)
        .toList();

    final chips = <Widget>[];

    chips.add(
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ActionChip(
          avatar: const Icon(Icons.home, size: 16),
          label: Text(isLocal ? '根目录' : '可访问根'),
          onPressed: () {
            if (isLocal) {
              provider.loadLocalDir('/');
            } else {
              provider.loadRemoteDir(sessionId, remoteRootRequestPath);
            }
          },
        ),
      ),
    );

    for (var i = 0; i < parts.length; i++) {
      final segmentPath = '$base/${parts.sublist(0, i + 1).join('/')}';
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ActionChip(
                label: Text(parts[i]),
                onPressed: () {
                  if (isLocal) {
                    provider.loadLocalDir(segmentPath);
                  } else {
                    provider.loadRemoteDir(sessionId, segmentPath);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return chips;
  }
}
