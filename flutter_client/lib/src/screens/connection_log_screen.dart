import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';

class ConnectionLogScreen extends StatelessWidget {
  const ConnectionLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接历史'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Consumer<ConnectionProvider>(
        builder: (context, provider, _) {
          final records = provider.recentConnections;
          if (records.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无连接历史', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      record.connectionType == 'p2p'
                          ? Icons.link
                          : Icons.cloud,
                      color: record.connectionType == 'p2p'
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text('${record.peerHostname} (${record.peerId})'),
                    subtitle: Text(
                      '${record.peerOs} | ${record.connectedAt.toString().substring(0, 16)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.replay),
                      tooltip: '再次连接',
                      onPressed: () {
                        context.go('/');
                      },
                    ),
                  ),
                );
              },
            );
        },
      ),
    );
  }
}
