import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/rdesk_bridge_service.dart';

class ChatProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final List<ChatMessage> _messages = [];
  int _unreadCount = 0;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  int get unreadCount => _unreadCount;

  Future<void> loadMessages(String sessionId) async {
    _messages
      ..clear()
      ..addAll(await _bridge.listChatMessages(sessionId));
    notifyListeners();
  }

  Future<void> sendMessage(String sessionId, String content) async {
    final message = await _bridge.sendChatMessage(sessionId, content);
    _messages.add(message);
    notifyListeners();
  }

  Future<void> receiveMessage(String sessionId, String sender, String content) async {
    await _bridge.injectRemoteMessage(sessionId, content);
    final message = ChatMessage(
      sender: sender,
      content: content,
      timestamp: DateTime.now(),
      isLocal: false,
    );
    _messages.add(message);
    _unreadCount++;
    notifyListeners();
  }

  void markRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _unreadCount = 0;
    notifyListeners();
  }
}
