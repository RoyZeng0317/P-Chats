class ChatMessage {
  final String documentId;
  final String from;
  final String to;
  String text;
  final DateTime timestamp;
  final String burnTimer; // 'off' | 'exit' | '1m' | '3m' | '5m'
  final String? mediaUrl;
  final String? mediaType;  // 'image' | 'video' | 'file'
  final String? fileName;
  bool isBurned;
  bool isSentByMe;
  bool recalled;
  bool edited;

  ChatMessage({
    required this.documentId,
    required this.from,
    required this.to,
    required this.text,
    required this.timestamp,
    this.burnTimer = 'off',
    this.mediaUrl,
    this.mediaType,
    this.fileName,
    this.isBurned = false,
    this.isSentByMe = false,
    this.recalled = false,
    this.edited = false,
  });

  bool get hasBurn => burnTimer != 'off';
  bool get hasMedia => mediaUrl != null && mediaType != null;
  bool get burnAfterRead => hasBurn;
}
