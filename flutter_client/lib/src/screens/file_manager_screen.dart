import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/file_transfer_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final provider = context.read<FileTransferProvider>();
    provider.loadLocalDir(provider.defaultLocalPath);
    provider.loadRemoteDir(widget.sessionId, '/');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/remote/${widget.sessionId}'),
        ),
      ),
      body: Column(
        children: [
          // Transfer progress bar
          Consumer<FileTransferProvider>(
            builder: (context, provider, _) {
              if (provider.transfers.isEmpty) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: provider.transfers.length,
                  itemBuilder: (context, index) {
                    return TransferProgressWidget(
                      transfer: provider.transfers[index],
                      onCancel: () =>
                          provider.cancelTransfer(provider.transfers[index].id),
                    );
                  },
                ),
              );
            },
          ),

          // Responsive file browser — Tab on narrow, dual-pane on wide
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

  /// Tab layout for narrow screens (phones in portrait).
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

  /// Dual-pane side-by-side layout for wide screens (tablets, landscape, desktop).
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
        // Path bar with horizontally scrollable breadcrumbs
        Consumer<FileTransferProvider>(
          builder: (context, provider, _) {
            final path = isLocal ? provider.localPath : provider.remotePath;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _buildBreadcrumbChips(context, path, provider),
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
              final files = isLocal ? provider.localFiles : provider.remoteFiles;
              if (files.isEmpty) {
                return const Center(child: Text('目录为空'));
              }
              return ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, index) {
                  return FileListTileWidget(
                    entry: files[index],
                    onTap: () {
                      if (files[index].isDir) {
                        final newPath =
                            '${isLocal ? provider.localPath : provider.remotePath}/${files[index].name}';
                        if (isLocal) {
                          provider.loadLocalDir(newPath);
                        } else {
                          provider.loadRemoteDir(sessionId, newPath);
                        }
                      }
                    },
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
    final parts =
        normalized.split('/').where((item) => item.isNotEmpty).toList();

    final chips = <Widget>[];

    // Root chip
    chips.add(
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ActionChip(
          avatar: const Icon(Icons.home, size: 16),
          label: const Text('根目录'),
          onPressed: () {
            if (isLocal) {
              provider.loadLocalDir('/');
            } else {
              provider.loadRemoteDir(sessionId, '/');
            }
          },
        ),
      ),
    );

    // Path segment chips
    for (var i = 0; i < parts.length; i++) {
      final segmentPath = '/${parts.sublist(0, i + 1).join('/')}';
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
