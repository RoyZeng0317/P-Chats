import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../widgets/message_bubble.dart';
import 'lock_screen.dart';

class ChatScreen extends StatefulWidget {
  final ChatService chatService;
  final String peerId;
  final String peerDisplayName;

  const ChatScreen({
    super.key,
    required this.chatService,
    required this.peerId,
    required this.peerDisplayName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _mediaService = MediaService();
  final List<ChatMessage> _messages = [];
  String _burnTimer = 'off';
  bool _uploading = false;
  StreamSubscription? _messageSub;
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    widget.chatService.listenToMessages(widget.peerId);
    _messageSub = widget.chatService.messageStream.listen(_onMessage);
    _eventSub = widget.chatService.eventStream.listen(_onEvent);
  }

  void _onMessage(ChatMessage msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
    if (!msg.isSentByMe && msg.hasBurn) {
      final delay = _burnDelay(msg.burnTimer);
      if (delay != null) {
        Future.delayed(delay, () {
          if (mounted) setState(() => _messages.removeWhere((m) => m.documentId == msg.documentId));
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String?;
    final docId = event['documentId'] as String? ?? '';

    switch (type) {
      case 'burn':
        setState(() {
          final idx = _messages.indexWhere((m) => m.documentId == docId);
          if (idx != -1) _messages[idx].isBurned = true;
        });
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _messages.removeWhere((m) => m.documentId == docId && m.isBurned));
        });

      case 'recall':
        setState(() {
          final idx = _messages.indexWhere((m) => m.documentId == docId);
          if (idx != -1) _messages[idx].recalled = true;
        });
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) setState(() => _messages.removeWhere((m) => m.documentId == docId && m.recalled));
        });

      case 'edit':
        final newText = event['newText'] as String? ?? '';
        setState(() {
          final idx = _messages.indexWhere((m) => m.documentId == docId);
          if (idx != -1) {
            _messages[idx].text = newText;
            _messages[idx].edited = true;
          }
        });
    }
  }

  Duration? _burnDelay(String timer) {
    switch (timer) {
      case '1m': return const Duration(minutes: 1);
      case '3m': return const Duration(minutes: 3);
      case '5m': return const Duration(minutes: 5);
      default: return null;
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.chatService.sendMessage(widget.peerId, text, burnTimer: _burnTimer);
    _textController.clear();
  }

  Future<void> _sendMedia(File file, String mediaType, {String? fileName}) async {
    setState(() => _uploading = true);
    try {
      final uid = widget.chatService.currentUserId ?? '';
      final resourceType = mediaType == 'file' ? 'raw' : mediaType;
      final result = await _mediaService.upload(uid, file, resourceType);
      if (result == null) {
        _showSnack('上傳失敗，請確認網路連線及 Cloudinary 設定');
        return;
      }
      await widget.chatService.sendMessage(
        widget.peerId,
        '',
        burnTimer: _burnTimer,
        mediaUrl: result.url,
        mediaType: mediaType,
        fileName: fileName,
        cloudinaryPublicId: result.publicId,
      );
    } catch (e) {
      _showSnack('上傳錯誤：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await _mediaService.pickImage();
    if (file == null) return;
    await _sendMedia(file, 'image');
  }

  Future<void> _pickVideo() async {
    final file = await _mediaService.pickVideo();
    if (file == null) return;
    await _sendMedia(file, 'video');
  }

  Future<void> _pickFile() async {
    final picked = await _mediaService.pickFile();
    if (picked == null) return;
    await _sendMedia(picked.file, 'file', fileName: picked.name);
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Colors.orange),
              title: const Text('傳送圖片'),
              onTap: () { Navigator.pop(context); _pickImage(); },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: Colors.orange),
              title: const Text('傳送影片'),
              onTap: () { Navigator.pop(context); _pickVideo(); },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.orange),
              title: const Text('傳送檔案'),
              onTap: () { Navigator.pop(context); _pickFile(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _lockPeerAndPop() async {
    ChatSessionLock.instance.lockPeer(widget.peerId);
    widget.chatService.stopListening();
    Navigator.of(context).pop();
  }

  void _showMessageOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            if (!msg.hasMedia)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('編輯訊息'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(msg);
                },
              ),
            ListTile(
              leading: const Icon(Icons.undo, color: Colors.red),
              title: const Text('收回訊息', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmRecall(msg);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(ChatMessage msg) async {
    final controller = TextEditingController(text: msg.text);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('編輯訊息'),
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != msg.text) {
      await widget.chatService.editMessage(msg.documentId, widget.peerId, result);
    }
  }

  Future<void> _confirmRecall(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('收回訊息'),
        content: const Text('收回後雙方都將看不到此訊息內容。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('收回'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.chatService.recallMessage(msg.documentId, widget.peerId);
    }
  }

  void _showBurnTimerPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('訊息焚燒時間', style: Theme.of(context).textTheme.titleMedium),
            ),
            _burnOption('off',  '關閉焚燒',         Icons.do_not_disturb_outlined, Colors.grey),
            _burnOption('exit', '對方退出後',        Icons.logout,                   Colors.orange),
            _burnOption('1m',   '1 分鐘後',          Icons.timer_outlined,            Colors.orange),
            _burnOption('3m',   '3 分鐘後',          Icons.timer_outlined,            Colors.deepOrange),
            _burnOption('5m',   '5 分鐘後',          Icons.timer_outlined,            Colors.red),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _burnOption(String value, String label, IconData icon, Color color) {
    final selected = _burnTimer == value;
    return ListTile(
      leading: Icon(icon, color: selected ? color : Colors.grey),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? color : null,
          fontWeight: selected ? FontWeight.bold : null,
        ),
      ),
      trailing: selected ? Icon(Icons.check, color: color) : null,
      onTap: () {
        setState(() => _burnTimer = value);
        Navigator.pop(context);
      },
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _eventSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    widget.chatService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasBurn = _burnTimer != 'off';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerDisplayName),
            const Text('E2E 加密', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          // Re-lock this chat room
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '重新鎖定此聊天室',
            onPressed: _lockPeerAndPop,
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasBurn)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '焚燒模式 — ${_burnTimerLabel(_burnTimer)}自動銷毀',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ],
              ),
            ),
          if (_uploading)
            LinearProgressIndicator(color: Colors.orange, backgroundColor: Colors.orange.shade50),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      '尚無訊息 — 訊息閱後即從伺服器刪除',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final msg = _messages[i];
                      return MessageBubble(
                        message: msg,
                        isMe: msg.isSentByMe,
                        onLongPress: (msg.isSentByMe && !msg.recalled)
                            ? () => _showMessageOptions(msg)
                            : null,
                      );
                    },
                  ),
          ),
          // Input bar
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, -1),
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              left: 8, right: 8, top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Row(
              children: [
                // Burn timer
                GestureDetector(
                  onTap: _showBurnTimerPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          color: hasBurn ? Colors.orange : Colors.grey,
                          size: 22,
                        ),
                        Text(
                          hasBurn ? _burnTimerShortLabel(_burnTimer) : '關閉',
                          style: TextStyle(
                            fontSize: 9,
                            color: hasBurn ? Colors.orange : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Attach
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 22),
                  color: Colors.grey,
                  onPressed: _uploading ? null : _showAttachMenu,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                // Text field
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: '輸入訊息（加密傳送）...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                // Send
                CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _burnTimerLabel(String timer) {
    switch (timer) {
      case 'exit': return '對方退出後';
      case '1m':   return '1 分鐘後';
      case '3m':   return '3 分鐘後';
      case '5m':   return '5 分鐘後';
      default:     return '';
    }
  }

  String _burnTimerShortLabel(String timer) {
    switch (timer) {
      case 'exit': return '退出';
      case '1m':   return '1m';
      case '3m':   return '3m';
      case '5m':   return '5m';
      default:     return '關閉';
    }
  }
}
