import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

class DeviceIdDisplay extends StatefulWidget {
  final String deviceId;
  final String temporaryPassword;
  final VoidCallback onRefreshPassword;

  const DeviceIdDisplay({
    super.key,
    required this.deviceId,
    required this.temporaryPassword,
    required this.onRefreshPassword,
  });

  @override
  State<DeviceIdDisplay> createState() => _DeviceIdDisplayState();
}

class _DeviceIdDisplayState extends State<DeviceIdDisplay>
    with SingleTickerProviderStateMixin {
  bool _showPassword = false;
  late AnimationController _refreshController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  String get _formattedId {
    final id = widget.deviceId;
    if (id.length == 9) {
      return '${id.substring(0, 3)} - ${id.substring(3, 6)} - ${id.substring(6, 9)}';
    }
    return id;
  }

  String get _maskedPassword {
    return _showPassword ? widget.temporaryPassword : '\u2022' * widget.temporaryPassword.length;
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.deviceId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('设备ID已复制'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copyPassword() {
    Clipboard.setData(ClipboardData(text: widget.temporaryPassword));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('密码已复制'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _refreshPassword() {
    _refreshController.forward(from: 0);
    widget.onRefreshPassword();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPassword = widget.temporaryPassword.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.3),
            colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.computer, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '本机信息',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 8),
                      SizedBox(width: 6),
                      Text('在线', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Device ID
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _formattedId,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _copyId,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制设备ID'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),

            Divider(color: colorScheme.outlineVariant, height: 32),

            // Password section
            Row(
              children: [
                const Icon(Icons.vpn_key, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '临时密码',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPassword = !_showPassword),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                        child: Row(
                          children: [
                            Text(
                              hasPassword ? _maskedPassword : '------',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              letterSpacing: _showPassword ? 4 : 6,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _showPassword ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: hasPassword ? _copyPassword : null,
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: '复制密码',
                  style: IconButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                  ),
                ),
                RotationTransition(
                  turns: Tween(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _refreshController,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: IconButton(
                    onPressed: _refreshPassword,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: '刷新临时密码',
                    style: IconButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: AppTheme.primaryBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '临时密码会定期刷新。建议通过电话或聊天工具单独发送给被控端用户。',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
