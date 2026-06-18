import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'lock_screen.dart';

const _appVersion = '1.0.0';

class SettingsScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  final VoidCallback onSignOut;

  const SettingsScreen({
    super.key,
    required this.chatService,
    required this.authService,
    required this.onSignOut,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Edit display name ─────────────────────────────────────────────────────────
  Future<void> _showEditDisplayNameDialog() async {
    final controller = TextEditingController(
        text: widget.chatService.currentDisplayName ?? '');
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('修改顯示名稱'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '最多 30 個字元，其他使用者看到的名稱。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '顯示名稱',
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
                final err = await widget.chatService
                    .updateDisplayName(controller.text);
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

  // ── Edit handle ──────────────────────────────────────────────────────────────
  Future<void> _showEditHandleDialog() async {
    final controller = TextEditingController(
        text: widget.chatService.currentHandle ?? '');
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('修改用戶 ID'),
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
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final err = await widget.chatService
                    .updateHandle(controller.text);
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

  // ── Change lock password ─────────────────────────────────────────────────────
  Future<void> _showChangePasswordDialog() async {
    final lock = ChatSessionLock.instance;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    bool obscure = true;
    final hasPassword = await lock.hasPassword();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(hasPassword ? '修改聊天室密碼' : '設定聊天室密碼'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPassword) ...[
                  TextField(
                    controller: oldCtrl,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: '舊密碼',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() => errorText = null),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: newCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '新密碼',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setD(() => obscure = !obscure),
                    ),
                  ),
                  onChanged: (_) => setD(() => errorText = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: '確認新密碼',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setD(() => errorText = null),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                if (hasPassword) {
                  final ok = await lock.verify(oldCtrl.text);
                  if (!ok) {
                    setD(() => errorText = '舊密碼錯誤');
                    return;
                  }
                }
                if (newCtrl.text.isEmpty) {
                  setD(() => errorText = '新密碼不得為空');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  setD(() => errorText = '兩次密碼不一致');
                  return;
                }
                await lock.setPassword(newCtrl.text);
                lock.lockAll();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('密碼已更新，請重新登入所有聊天室')),
                  );
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除帳號'),
        content: const Text(
          '刪除帳號後，所有資料將永久移除且無法還原。確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.chatService.deleteUserData();
    final err = await widget.authService.deleteAccount();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
    // Firebase auth state change triggers navigation automatically
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.chatService.currentHandle;
    final displayName = widget.chatService.currentDisplayName;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // ── Profile section ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('個人資料',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Text(
                (displayName?.isNotEmpty == true
                        ? displayName!
                        : handle ?? '?')[0]
                    .toUpperCase(),
                style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              displayName?.isNotEmpty == true ? displayName! : '尚未設定',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text('顯示名稱'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showEditDisplayNameDialog,
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey.shade100,
              child: Text(
                '@',
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              handle != null ? '@$handle' : '尚未設定',
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: const Text('用戶 ID'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showEditHandleDialog,
          ),
          const Divider(height: 1, indent: 16),

          // ── Security section ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('安全性',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.orange),
            title: const Text('聊天室密碼'),
            subtitle: const Text('保護所有加密聊天室的入口'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),
          const Divider(height: 1, indent: 16),

          // ── About section ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('關於',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          ListTile(
            leading: const Icon(Icons.security, color: Colors.orange),
            title: const Text('端到端加密'),
            subtitle: const Text(
                'X25519 金鑰交換 · AES-256-GCM 加密\n訊息閱後即從伺服器刪除'),
            isThreeLine: true,
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.orange),
            title: const Text('版本'),
            trailing: Text(
              _appVersion,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          const Divider(height: 1, indent: 16),

          // ── Danger zone ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('帳號管理',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined,
                color: Colors.red),
            title: const Text('刪除帳號',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('永久刪除帳號及所有資料'),
            trailing: const Icon(Icons.chevron_right, color: Colors.red),
            onTap: _confirmDeleteAccount,
          ),
          const Divider(height: 1, indent: 16),

          // ── Logout ───────────────────────────────────────────────────────
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('登出',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _confirmSignOut,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
