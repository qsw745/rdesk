import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/theme.dart';

class IncomingConnectionRequest {
  final String peerId;
  final String peerHostname;
  final String peerPlatform;
  final DateTime requestedAt;

  const IncomingConnectionRequest({
    required this.peerId,
    required this.peerHostname,
    required this.peerPlatform,
    required this.requestedAt,
  });
}

enum IncomingConnectionAction { accept, reject, timeout }

enum IncomingConnectionPresentation { centeredDialog, desktopBottomRight }

const _incomingRequestTimeoutSeconds = 55;

Future<IncomingConnectionAction> showIncomingConnectionDialog(
  BuildContext context,
  IncomingConnectionRequest request, {
  IncomingConnectionPresentation presentation =
      IncomingConnectionPresentation.centeredDialog,
}) async {
  switch (presentation) {
    case IncomingConnectionPresentation.centeredDialog:
      final result = await showDialog<IncomingConnectionAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _IncomingConnectionDialogContent(
          request: request,
          presentation: presentation,
        ),
      );
      return result ?? IncomingConnectionAction.timeout;
    case IncomingConnectionPresentation.desktopBottomRight:
      return _showDesktopIncomingConnectionPopup(context, request);
  }
}

Future<IncomingConnectionAction> _showDesktopIncomingConnectionPopup(
  BuildContext context,
  IncomingConnectionRequest request,
) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    // Fallback to a normal dialog when overlay is not ready yet,
    // instead of instantly timing out and auto-rejecting the request.
    final result = await showDialog<IncomingConnectionAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IncomingConnectionDialogContent(
        request: request,
        presentation: IncomingConnectionPresentation.centeredDialog,
      ),
    );
    return result ?? IncomingConnectionAction.timeout;
  }

  final completer = Completer<IncomingConnectionAction>();
  OverlayEntry? entry;

  void finish(IncomingConnectionAction action) {
    if (completer.isCompleted) return;
    completer.complete(action);
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final bottomSafe = MediaQuery.of(ctx).padding.bottom;
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              right: 16,
              bottom: 16 + bottomSafe,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
                child: _IncomingConnectionDialogContent(
                  request: request,
                  presentation:
                      IncomingConnectionPresentation.desktopBottomRight,
                  onFinished: finish,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  overlay.insert(entry!);

  return completer.future.timeout(
    const Duration(seconds: _incomingRequestTimeoutSeconds + 2),
    onTimeout: () {
      finish(IncomingConnectionAction.timeout);
      return IncomingConnectionAction.timeout;
    },
  );
}

class _IncomingConnectionDialogContent extends StatefulWidget {
  final IncomingConnectionRequest request;
  final IncomingConnectionPresentation presentation;
  final ValueChanged<IncomingConnectionAction>? onFinished;

  const _IncomingConnectionDialogContent({
    required this.request,
    required this.presentation,
    this.onFinished,
  });

  @override
  State<_IncomingConnectionDialogContent> createState() =>
      _IncomingConnectionDialogContentState();
}

class _IncomingConnectionDialogContentState
    extends State<_IncomingConnectionDialogContent>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;

  bool get _isDesktopRightBottom =>
      widget.presentation == IncomingConnectionPresentation.desktopBottomRight;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _incomingRequestTimeoutSeconds;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _complete(IncomingConnectionAction.timeout);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _complete(IncomingConnectionAction action) {
    _timer?.cancel();
    if (widget.onFinished != null) {
      widget.onFinished!(action);
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = _buildPanel(context);
    if (_isDesktopRightBottom) {
      return panel;
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E2E)
          : Colors.white,
      child: panel,
    );
  }

  Widget _buildPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final platformIcon = _platformIcon(widget.request.peerPlatform);
    final hPad = _isDesktopRightBottom ? 18.0 : 28.0;
    final vPad = _isDesktopRightBottom ? 18.0 : 28.0;
    final iconSize = _isDesktopRightBottom ? 56.0 : 68.0;
    final titleSize = _isDesktopRightBottom ? 22.0 : 28.0;
    final description = _isDesktopRightBottom ? '有设备请求连接你的桌面' : '有设备请求远程控制你的桌面';

    return Container(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(_isDesktopRightBottom ? 20 : 28),
        border: _isDesktopRightBottom
            ? Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06),
              )
            : null,
        boxShadow: _isDesktopRightBottom
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + _pulseController.value * 0.08;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.phonelink_ring_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '远程连接请求',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: titleSize,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: isDark ? Colors.white54 : AppTheme.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF242A3D) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(platformIcon, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.peerHostname.isNotEmpty
                            ? widget.request.peerHostname
                            : widget.request.peerId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${widget.request.peerId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  value: _remainingSeconds / _incomingRequestTimeoutSeconds,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade200,
                  strokeWidth: 3,
                ),
              ),
              Text(
                '$_remainingSeconds',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => _complete(IncomingConnectionAction.reject),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.errorRed),
                      foregroundColor: AppTheme.errorRed,
                    ),
                    child: const Text('拒绝'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: () => _complete(IncomingConnectionAction.accept),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.successGreen,
                    ),
                    child: const Text('接受'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
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
