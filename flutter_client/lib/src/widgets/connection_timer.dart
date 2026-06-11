import 'dart:async';
import 'package:flutter/material.dart';

/// Displays elapsed connection time as HH:MM:SS.
class ConnectionTimer extends StatefulWidget {
  final DateTime startTime;
  final TextStyle? style;

  const ConnectionTimer({
    super.key,
    required this.startTime,
    this.style,
  });

  @override
  State<ConnectionTimer> createState() => _ConnectionTimerState();
}

class _ConnectionTimerState extends State<ConnectionTimer> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  void _updateElapsed() {
    setState(() {
      _elapsed = DateTime.now().difference(widget.startTime);
      if (_elapsed.isNegative) _elapsed = Duration.zero;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(_elapsed),
      style: widget.style ??
          const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}
