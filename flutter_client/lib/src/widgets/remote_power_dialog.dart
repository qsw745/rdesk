import 'package:flutter/material.dart';

/// Asks before restarting or shutting down the other computer: it ends the
/// session and may cost the person there their unsaved work. Returns the
/// action to send, or null when cancelled.
Future<String?> confirmRemotePower(BuildContext context,
    {required bool shutdown}) async {
  final verb = shutdown ? '关机' : '重启';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$verb对方的电脑？'),
      content: Text(shutdown
          ? '对方电脑约 10 秒后关机，本次远程控制会断开，未保存的内容可能丢失。'
              '关机后需要远程开机或有人按电源键才能再次连接。'
          : '对方电脑约 10 秒后重启，本次远程控制会断开，未保存的内容可能丢失。'
              '重启后要等对方登录 Windows 才能再次连接。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(verb)),
      ],
    ),
  );
  if (confirmed != true) return null;
  return shutdown ? 'power_shutdown' : 'power_restart';
}
