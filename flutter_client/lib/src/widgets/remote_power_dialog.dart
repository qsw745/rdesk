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

/// Asks, sends, then says what the other computer answered. It only claims
/// the restart or shutdown is on its way once the other side accepted it:
/// an older version there does not know these actions and declines.
Future<void> requestRemotePower(
  BuildContext context, {
  required bool shutdown,
  required Future<bool> Function(String action) send,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await confirmRemotePower(context, shutdown: shutdown);
  if (action == null) return;
  final verb = shutdown ? '关机' : '重启';
  var accepted = false;
  try {
    accepted = await send(action);
  } on Exception catch (error) {
    debugPrint('[RDesk] power action not sent: ${error.runtimeType}');
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(accepted
            ? '对方电脑已接受，约 10 秒后$verb'
            : '对方电脑没有$verb：那边的随控版本可能较旧，或当前无法操作')));
}
