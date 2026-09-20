import 'package:flutter/material.dart';

class SettingsSections extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final List<Widget> children;
  const SettingsSections(
      {super.key,
      required this.selected,
      required this.onSelected,
      required this.children});
  static const labels = {
    'general': '常规',
    'security': '安全',
    'network': '网络',
    'about': '关于'
  };
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, children: [
                  for (final entry in labels.entries)
                    TextButton(
                        onPressed: () => onSelected(entry.key),
                        style: TextButton.styleFrom(
                            backgroundColor: entry.key == selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null),
                        child: Text(entry.value,
                            style: const TextStyle(fontSize: 15)))
                ]))),
        const SizedBox(height: 12),
        Expanded(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                        children: children)))),
      ]);
}
