import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/address_book.dart';
import '../providers/address_book_provider.dart';
import '../providers/connection_provider.dart';
import '../utils/theme.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<AddressBookProvider>().load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('地址簿'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: '添加设备',
            onPressed: () => _showAddDeviceDialog(context),
          ),
        ],
      ),
      body: Consumer<AddressBookProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索设备 ID 或备注',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              provider.setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),

              // Group filter chips
              if (provider.groups.length > 1)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('全部'),
                          selected: provider.filterGroup.isEmpty,
                          onSelected: (_) => provider.setFilterGroup(''),
                        ),
                      ),
                      ...provider.groups.map((g) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(g),
                              selected: provider.filterGroup == g,
                              onSelected: (_) => provider.setFilterGroup(
                                  provider.filterGroup == g ? '' : g),
                            ),
                          )),
                    ],
                  ),
                ),

              // Device list
              Expanded(
                child: provider.entries.isEmpty
                    ? _EmptyState(
                        onAdd: () => _showAddDeviceDialog(context),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: provider.entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _DeviceCard(
                            entry: provider.entries[index],
                            cardBg: cardBg,
                            isDark: isDark,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddDeviceDialog(BuildContext context) {
    final idController = TextEditingController();
    final aliasController = TextEditingController();
    String selectedGroup = '默认';
    final provider = context.read<AddressBookProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1E2D) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_add_outlined,
                            color: AppTheme.primaryBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text('添加设备',
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                      labelText: '设备 ID',
                      prefixIcon: Icon(Icons.devices_outlined, size: 20),
                      hintText: '输入对方的设备 ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: '备注名称',
                      prefixIcon: Icon(Icons.label_outline, size: 20),
                      hintText: '例如：公司电脑',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: '分组',
                      prefixIcon: Icon(Icons.folder_outlined, size: 20),
                    ),
                    items: [
                      ...provider.groups.map((g) => DropdownMenuItem(
                            value: g,
                            child: Text(g),
                          )),
                      const DropdownMenuItem(
                        value: '__new__',
                        child: Text('+ 新建分组'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == '__new__') {
                        final name = await _showNewGroupDialog(ctx);
                        if (name != null && name.isNotEmpty) {
                          await provider.addGroup(name);
                          setSheetState(() => selectedGroup = name);
                        }
                      } else if (v != null) {
                        setSheetState(() => selectedGroup = v);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        final id = idController.text.trim();
                        if (id.isEmpty) return;
                        provider.addEntry(
                          deviceId: id,
                          alias: aliasController.text.trim(),
                          group: selectedGroup,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('添加'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showNewGroupDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分组名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.contacts_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('地址簿为空',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('添加常用设备以便快速连接',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加设备'),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final AddressBookEntry entry;
  final Color cardBg;
  final bool isDark;

  const _DeviceCard({
    required this.entry,
    required this.cardBg,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final platformIcon = _platformIcon(entry.platform);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: InkWell(
        onTap: () => _quickConnect(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(platformIcon,
                    color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.alias.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              entry.deviceId,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isDark ? Colors.white38 : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            entry.group,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.accentPurple,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (entry.lastConnectedAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatLastConnect(entry.lastConnectedAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white38
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20,
                    color: isDark ? Colors.white38 : Colors.grey),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'connect', child: Text('连接')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'delete') {
                    context.read<AddressBookProvider>().removeEntry(entry.deviceId);
                  } else if (v == 'connect') {
                    _quickConnect(context);
                  } else if (v == 'edit') {
                    _showEditDialog(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _quickConnect(BuildContext context) {
    _showPasswordAndConnect(context);
  }

  void _showPasswordAndConnect(BuildContext outerContext) {
    final passwordController = TextEditingController();
    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1A1E2D) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '连接到 ${entry.displayName}',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('ID: ${entry.deviceId}',
                  style: TextStyle(
                      fontSize: 13,
                      color: dark ? Colors.white38 : AppTheme.textMuted)),
              const SizedBox(height: 20),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '连接密码',
                  prefixIcon: Icon(Icons.lock_outline, size: 20),
                  hintText: '输入临时密码或永久密码',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    final pw = passwordController.text.trim();
                    if (pw.isEmpty) return;
                    Navigator.pop(ctx);
                    final connectionProvider =
                        outerContext.read<ConnectionProvider>();
                    await connectionProvider.connect(entry.deviceId, pw);
                    outerContext
                        .read<AddressBookProvider>()
                        .markConnected(entry.deviceId);
                  },
                  child: const Text('连接'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context) {
    final aliasController = TextEditingController(text: entry.alias);
    final provider = context.read<AddressBookProvider>();
    var selectedGroup = entry.group;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1A1E2D) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('编辑设备',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: '备注名称',
                      prefixIcon: Icon(Icons.label_outline, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: '分组',
                      prefixIcon: Icon(Icons.folder_outlined, size: 20),
                    ),
                    items: provider.groups
                        .map((g) =>
                            DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setSheetState(() => selectedGroup = v);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        provider.updateEntry(
                          entry.deviceId,
                          alias: aliasController.text.trim(),
                          group: selectedGroup,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatLastConnect(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚连接';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
      case 'mac':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.laptop_windows;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.devices_outlined;
    }
  }
}
