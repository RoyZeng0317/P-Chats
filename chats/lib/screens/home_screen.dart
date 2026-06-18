import 'package:flutter/material.dart';
import '../models/user_info.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'lock_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ChatService _chatService;
  int _tabIndex = 0;
  bool _loading = true;
  final List<ChatUser> _recentChats = [];

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

  void _addToRecent(ChatUser user) {
    setState(() {
      _recentChats.removeWhere((u) => u.userId == user.userId);
      _recentChats.insert(0, user);
    });
  }

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
    _addToRecent(user);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _SearchTab(chatService: _chatService, onOpenChat: _openChat),
          _RecentTab(recentChats: _recentChats, onOpenChat: _openChat),
          SettingsScreen(
            chatService: _chatService,
            authService: widget.authService,
            onSignOut: _signOut,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '首頁',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: '訊息',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}

// ── 首頁 tab: search ──────────────────────────────────────────────────────────

class _SearchTab extends StatefulWidget {
  final ChatService chatService;
  final Future<void> Function(ChatUser) onOpenChat;

  const _SearchTab({required this.chatService, required this.onOpenChat});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _searchController = TextEditingController();
  bool _searching = false;
  ChatUser? _searchResult;
  bool _searched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searched = false;
      _searchResult = null;
    });
    try {
      final user = await widget.chatService.searchUser(query);
      if (mounted) setState(() { _searchResult = user; _searched = true; });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.chatService.currentHandle;

    return Scaffold(
      appBar: AppBar(title: const Text('P Chats')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // E2E badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // My handle card
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
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  '其他使用者需輸入此 ID 才能找到你（可至設定修改）',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Search
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
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('搜尋'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search result
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
                        style:
                            TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              )
            else
              _UserCard(
                user: _searchResult!,
                trailing: FilledButton(
                  onPressed: () => widget.onOpenChat(_searchResult!),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange),
                  child: const Text('開始對話'),
                ),
                onTap: () => widget.onOpenChat(_searchResult!),
              ),
          ],
        ],
      ),
    );
  }
}

// ── 訊息 tab: recent chats ────────────────────────────────────────────────────

class _RecentTab extends StatelessWidget {
  final List<ChatUser> recentChats;
  final Future<void> Function(ChatUser) onOpenChat;

  const _RecentTab(
      {required this.recentChats, required this.onOpenChat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('訊息')),
      body: recentChats.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('尚無最近對話',
                      style:
                          TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('從首頁搜尋用戶來開始對話',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade400)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: recentChats.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final u = recentChats[i];
                return _UserCard(
                  user: u,
                  onTap: () => onOpenChat(u),
                );
              },
            ),
    );
  }
}

// ── Shared user card widget ───────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final ChatUser user;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _UserCard({required this.user, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade100),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          backgroundImage: user.photoURL.isNotEmpty
              ? NetworkImage(user.photoURL)
              : null,
          child: user.photoURL.isEmpty
              ? Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Text(user.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('@${user.userHandle}',
            style:
                TextStyle(color: Colors.orange.shade700, fontSize: 13)),
        trailing: trailing ??
            const Icon(Icons.chat_bubble_outline, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
