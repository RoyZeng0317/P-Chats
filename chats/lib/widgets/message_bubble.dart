import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (message.recalled) return _buildRecalledBubble(context);

    final burn = message.hasBurn;
    final bgColor = isMe
        ? (burn ? Colors.orange.shade100 : Colors.blue.shade100)
        : (burn ? Colors.orange.shade50 : Colors.grey.shade200);
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
      bottomRight: isMe ? Radius.zero : const Radius.circular(16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius),
              padding: message.hasMedia && message.mediaType != 'file'
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.hasMedia) _buildMediaContent(context),
                  if (message.text.isNotEmpty) ...[
                    if (message.hasMedia) const SizedBox(height: 4),
                    Padding(
                      padding: message.hasMedia
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                          : EdgeInsets.zero,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (burn)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.local_fire_department, size: 14,
                                  color: Colors.orange.shade700),
                            ),
                          Flexible(
                            child: Text(message.text, style: const TextStyle(fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Meta row
                  Padding(
                    padding: message.hasMedia && message.mediaType != 'file'
                        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                        : const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!message.hasMedia && burn)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.local_fire_department, size: 14,
                                color: Colors.orange.shade700),
                          ),
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                        if (message.edited) ...[
                          const SizedBox(width: 4),
                          Text('已編輯',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                        if (burn) ...[
                          const SizedBox(width: 6),
                          Text(_burnLabel(message.burnTimer),
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade600)),
                        ],
                        if (message.isBurned) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.auto_delete, size: 12, color: Colors.orange.shade700),
                          Text(' 已焚燒',
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    final type = message.mediaType!;
    final url = message.mediaUrl!;

    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: MediaQuery.of(context).size.width * 0.6,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: MediaQuery.of(context).size.width * 0.6,
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                  color: Colors.orange,
                ),
              ),
            );
          },
          errorBuilder: (_, _, _) => const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
      );
    }

    if (type == 'video') {
      return _VideoBubble(url: url);
    }

    // file
    return _buildFileTile(url);
  }

  Widget _buildFileTile(String url) {
    final name = message.fileName ?? '檔案';
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 32, color: Colors.orange),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                style: const TextStyle(fontSize: 13, color: Colors.blue,
                    decoration: TextDecoration.underline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecalledBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.remove_circle_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  isMe ? '你收回了一則訊息' : '對方收回了一則訊息',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _burnLabel(String timer) {
    switch (timer) {
      case 'exit': return '退出後';
      case '1m':   return '1 分鐘';
      case '3m':   return '3 分鐘';
      case '5m':   return '5 分鐘';
      default:     return '';
    }
  }
}

class _VideoBubble extends StatefulWidget {
  final String url;
  const _VideoBubble({required this.url});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.6;

    if (!_initialized) {
      return SizedBox(
        width: width,
        height: 140,
        child: const Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                child: AnimatedOpacity(
                  opacity: _controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
