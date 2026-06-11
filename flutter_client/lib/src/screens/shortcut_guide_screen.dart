import 'package:flutter/material.dart';

class ShortcutGuideScreen extends StatelessWidget {
  const ShortcutGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const shortcuts = <({String key, String action})>[
      (key: 'Cmd/Ctrl + C', action: '复制'),
      (key: 'Cmd/Ctrl + V', action: '粘贴'),
      (key: 'Cmd/Ctrl + X', action: '剪切'),
      (key: 'Cmd/Ctrl + Z', action: '撤销'),
      (key: 'Cmd/Ctrl + A', action: '全选'),
      (key: 'Enter', action: '回车'),
      (key: 'Backspace', action: '删除'),
      (key: 'Esc', action: '取消/返回'),
      (key: 'Tab', action: '切换焦点'),
      (key: 'Arrow Keys', action: '方向键操作'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('快捷键')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Text(
                '移动端会将常用组合键映射到远端系统，Mac 与 Windows 默认都支持 Cmd/Ctrl 组合输入。',
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...shortcuts.map(
            (item) => Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                title: Text(
                  item.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(item.action),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
