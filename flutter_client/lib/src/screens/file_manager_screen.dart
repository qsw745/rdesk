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

class _FileManagerScreenState extends State<FileManagerScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<FileTransferProvider>();
    provider.loadLocalDir(provider.defaultLocalPath);
    provider.loadRemoteDir(widget.sessionId, '/');
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

          // Dual-pane file browser
          Expanded(
            child: Row(
              children: [
                // Local files
                Expanded(
                  child: _FileBrowser(
                    title: '本地',
                    isLocal: true,
                    sessionId: widget.sessionId,
                  ),
                ),
                const VerticalDivider(width: 1),
                // Remote files
                Expanded(
                  child: _FileBrowser(
                    title: '远程',
                    isLocal: false,
                    sessionId: widget.sessionId,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        // Path bar
        Consumer<FileTransferProvider>(
          builder: (context, provider, _) {
            final path = isLocal ? provider.localPath : provider.remotePath;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _breadcrumbs(path).map((segment) {
                      return ActionChip(
                        label: Text(segment),
                        onPressed: () {},
                      );
                    }).toList(),
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
                        final newPath = '${isLocal ? provider.localPath : provider.remotePath}/${files[index].name}';
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

  List<String> _breadcrumbs(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((item) => item.isNotEmpty).toList();
    if (parts.isEmpty) return ['根目录'];
    return parts;
  }
}
