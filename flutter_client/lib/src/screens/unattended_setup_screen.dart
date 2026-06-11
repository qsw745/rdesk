import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';

class UnattendedSetupScreen extends StatefulWidget {
  const UnattendedSetupScreen({super.key});

  @override
  State<UnattendedSetupScreen> createState() => _UnattendedSetupScreenState();
}

class _UnattendedSetupScreenState extends State<UnattendedSetupScreen> {
  int _currentStep = 0;
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final steps = _buildSteps(settings, isDark);

    return Scaffold(
      appBar: AppBar(title: const Text('无人值守设置')),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppTheme.primaryBlue,
              ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < steps.length - 1) {
              setState(() => _currentStep++);
            } else {
              settings.setUnattendedMode(true);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('无人值守模式已开启'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.of(context).pop();
            }
          },
          onStepTapped: (step) => setState(() => _currentStep = step),
          controlsBuilder: (context, details) {
            final isLast = _currentStep == steps.length - 1;
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: Text(isLast ? '完成设置' : '下一步'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: Text(_currentStep == 0 ? '取消' : '上一步'),
                  ),
                ],
              ),
            );
          },
          steps: steps,
        ),
      ),
    );
  }

  List<Step> _buildSteps(SettingsProvider settings, bool isDark) {
    final hasPassword = settings.permanentPassword != null &&
        settings.permanentPassword!.isNotEmpty;

    return [
      Step(
        title: const Text('设置永久密码'),
        subtitle: Text(hasPassword ? '已设置' : '未设置'),
        isActive: _currentStep >= 0,
        state: hasPassword ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '永久密码用于无人值守时远程连接。设置后即使没有人在被控端操作，也可以通过此密码连接。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '永久密码',
                hintText: '至少6位',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () {
                    final pwd = _passwordController.text.trim();
                    if (pwd.length >= 6) {
                      settings.setPermanentPassword(pwd);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('永久密码已保存'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      Step(
        title: const Text('开启自动接受连接'),
        subtitle: Text(settings.autoAccept ? '已开启' : '未开启'),
        isActive: _currentStep >= 1,
        state: settings.autoAccept ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '开启自动接受后，受信设备可以直接连接，无需手动确认。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('自动接受连接'),
              value: settings.autoAccept,
              onChanged: settings.setAutoAccept,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
      Step(
        title: Text(_platformStartupTitle),
        subtitle: const Text('请按系统设置操作'),
        isActive: _currentStep >= 2,
        state: StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _platformStartupInstructions,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: AppTheme.primaryBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '设置完成后，设备重启时 RDesk 会自动运行并等待远程连接。',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  String get _platformStartupTitle {
    if (Platform.isAndroid) return '开启后台保持与自启动';
    if (Platform.isMacOS) return '添加到登录项';
    return '配置开机自启';
  }

  String get _platformStartupInstructions {
    if (Platform.isAndroid) {
      return '1. 前往「设置 > 应用 > RDesk > 电池」，选择「不受限制」\n'
          '2. 在「设置 > 应用 > 自启动管理」中允许 RDesk 自启动\n'
          '3. 确保无障碍服务已开启（在 RDesk 设置页的安卓被控端区域操作）';
    }
    if (Platform.isMacOS) {
      return '1. 打开「系统设置 > 通用 > 登录项与扩展」\n'
          '2. 点击「+」添加 RDesk 到登录项\n'
          '3. 确保 RDesk 拥有「屏幕录制」和「辅助功能」权限';
    }
    return '请根据您的操作系统配置应用开机自启动。';
  }
}
