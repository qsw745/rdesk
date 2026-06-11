import 'package:flutter/material.dart';

class GestureGuideScreen extends StatelessWidget {
  const GestureGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <({IconData icon, String title, String desc})>[
      (
        icon: Icons.touch_app_rounded,
        title: '单击',
        desc: '向远端发送一次点击。',
      ),
      (
        icon: Icons.ads_click_rounded,
        title: '双击',
        desc: '执行双击操作，也可用于显示/隐藏工具栏。',
      ),
      (
        icon: Icons.pan_tool_alt_rounded,
        title: '长按',
        desc: '向远端发送长按，可用于拖拽前准备。',
      ),
      (
        icon: Icons.open_with_rounded,
        title: '拖拽',
        desc: '按住并移动，映射为远端拖动手势。',
      ),
      (
        icon: Icons.zoom_in_map_rounded,
        title: '双指缩放',
        desc: '在查看模式下缩放远端画面。',
      ),
      (
        icon: Icons.swipe_rounded,
        title: '双指滑动',
        desc: '移动可视区域，适合大分辨率桌面。',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('操作手势')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              leading: Icon(item.icon, size: 22),
              title: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.desc),
              ),
            ),
          );
        },
      ),
    );
  }
}
