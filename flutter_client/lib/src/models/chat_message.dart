class ChatMessage {
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isLocal;

  const ChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.isLocal,
  });
}
