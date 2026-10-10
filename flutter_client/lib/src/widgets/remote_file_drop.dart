import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/rdesk_bridge_service.dart';
import '../utils/platform_capabilities.dart';

/// Lets files be dragged from this computer onto the remote picture; they
/// are saved in the other computer's Downloads folder. Each file reports
/// what really happened to it.
class RemoteFileDrop extends StatefulWidget {
  const RemoteFileDrop({
    super.key,
    required this.sessionId,
    required this.child,
    this.send,
  });

  final String sessionId;
  final Widget child;

  /// Replaceable for tests; defaults to the real transfer.
  final Future<FileSendResult> Function(String sessionId, String path)? send;

  @override
  State<RemoteFileDrop> createState() => RemoteFileDropState();
}

class RemoteFileDropState extends State<RemoteFileDrop> {
  bool _hovering = false;
  int _sending = 0;

  @visibleForTesting
  int get sending => _sending;

  Future<void> sendFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    if (context.read<SessionProvider>().viewOnly) {
      say('当前是仅观看，不能向对方发送文件');
      return;
    }
    final send = widget.send ?? RdeskBridgeService.instance.sendFileToHost;
    setState(() => _sending += paths.length);
    var saved = 0;
    final outcomes = <String>[];
    final problems = <String>[];
    for (final path in paths) {
      final name = path.split(RegExp(r'[/\\]')).last;
      say('正在发送「$name」…');
      var ok = false;
      String outcome;
      try {
        final result = await send(widget.sessionId, path);
        ok = result.saved;
        outcome = result.describe(name);
      } on Exception catch (error) {
        debugPrint('[RDesk] dropped file not sent: ${error.runtimeType}');
        outcome = '「$name」发送失败';
      }
      if (!mounted) return;
      setState(() => _sending--);
      outcomes.add(outcome);
      if (ok) {
        saved++;
      } else {
        problems.add(outcome);
      }
    }
    // The next "sending…" replaces each file's own message at once, so the
    // last word covers every file: none of the failures may go unseen.
    if (outcomes.length == 1) {
      say(outcomes.single);
    } else if (problems.isEmpty) {
      say('$saved 个文件已保存到对方电脑的「下载」文件夹');
    } else {
      say('已保存 $saved 个文件到对方电脑的「下载」文件夹；${problems.join('；')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.current.isDesktop) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        sendFiles([for (final file in details.files) file.path]);
      },
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_hovering || _sending > 0)
          IgnorePointer(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: _hovering ? 0.18 : 0),
                border: _hovering
                    ? Border.all(color: scheme.primary, width: 3)
                    : null,
              ),
              child: _hovering
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Text('松开发送到对方电脑的「下载」文件夹',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    )
                  : null,
            ),
          ),
      ]),
    );
  }
}
