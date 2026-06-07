import 'package:flutter/material.dart';
import '../models/user_info.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'lock_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ChatService _chatService;
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  ChatUser? _searchResult;
  bool _searched = false; // whether a search was attempted

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(widget.authService.encryptionService);
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      await _chatService.initialize(widget.authService.currentUser!);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signOut() async {
    ChatSessionLock.instance.lockAll();
    await widget.authService.signOut();
  }

  // ── Handle edit ─────────────────────────────────────────────────────────────
  Future<void> _showEditHandleDialog() async {
    final controller =
        TextEditingController(text: _chatService.currentHandle ?? '');
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('設定用戶 ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '3–20 字元，只能使用英文小寫字母、數字與底線 (_)。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '用戶 ID',
                  prefixText: '@',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onChanged: (_) => setD(() => errorText = null),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final err =
                    await _chatService.updateHandle(controller.text);
                if (err != null) {
                  setD(() => errorText = err);
                } else {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search ──────────────────────────────────────────────────────────────────
  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() { _searching = true; _searched = false; _searchResult = null; });
    try {
      final user = await _chatService.searchUser(query);
      if (mounted) setState(() { _searchResult = user; _searched = true; });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Open chat (with lock gate) ───────────────────────────────────────────────
  Future<void> _openChat(ChatUser user) async {
    final lock = ChatSessionLock.instance;

    if (!lock.isPeerUnlocked(user.userId)) {
      final hasPassword = await lock.hasPassword();
      if (!mounted) return;
      final unlocked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LockScreen(peerId: user.userId, isSetup: !hasPassword),
        ),
      );
      if (unlocked != true) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatService: _chatService,
          peerId: user.userId,
          peerDisplayName: user.displayName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('P Chats')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final handle = _chatService.currentHandle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: _signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── E2E badge ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '端到端加密 · 訊息閱後即從伺服器刪除',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── My handle card ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的用戶 ID',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        handle != null ? '@$handle' : '尚未設定',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('編輯'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.orange),
                      onPressed: _showEditHandleDialog,
                    ),
                  ],
                ),
                Text(
                  '其他使用者需要輸入此 ID 才能找到你',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Search ─────────────────────────────────────────────────────────
          Text('搜尋用戶',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '輸入對方的用戶 ID…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _searching ? null : _search,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                ),
                child: _searching
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('搜尋'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search result ──────────────────────────────────────────────────
          if (_searched) ...[
            if (_searchResult == null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_off_outlined,
                        color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Text('找不到此用戶 ID',
                        style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              )
            else
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade100),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    backgroundImage: _searchResult!.photoURL.isNotEmpty
                        ? NetworkImage(_searchResult!.photoURL)
                        : null,
                    child: _searchResult!.photoURL.isEmpty
                        ? Text(
                            _searchResult!.displayName.isNotEmpty
                                ? _searchResult!.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  title: Text(
                    _searchResult!.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('@${_searchResult!.userHandle}',
                      style: TextStyle(
                          color: Colors.orange.shade700, fontSize: 13)),
                  trailing: FilledButton(
                    onPressed: () => _openChat(_searchResult!),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange),
                    child: const Text('開始對話'),
                  ),
                  onTap: () => _openChat(_searchResult!),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
