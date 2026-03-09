import 'package:flutter/material.dart';

import '../models/file_entry.dart';

class TransferProgressWidget extends StatelessWidget {
  final TransferProgress transfer;
  final VoidCallback onCancel;

  const TransferProgressWidget({
    super.key,
    required this.transfer,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (transfer.state) {
      TransferState.pending => '等待中',
      TransferState.transferring => '传输中',
      TransferState.completed => '已完成',
      TransferState.failed => '失败',
      TransferState.cancelled => '已取消',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    transfer.isUpload ? Icons.upload : Icons.download,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      transfer.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (transfer.state == TransferState.transferring)
                    IconButton(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: transfer.progress),
              const SizedBox(height: 8),
              Text(
                '$status • ${(transfer.progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
