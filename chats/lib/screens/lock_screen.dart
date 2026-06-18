import 'package:flutter/material.dart';
import '../services/database_service.dart';

// Keeps track of which peer rooms have been unlocked in this session.
class ChatSessionLock {
  ChatSessionLock._();
  static final ChatSessionLock instance = ChatSessionLock._();

  final Set<String> _unlockedPeers = {};
  bool _appUnlocked = false;

  bool get isAppUnlocked => _appUnlocked;

  bool isPeerUnlocked(String peerId) =>
      _appUnlocked && _unlockedPeers.contains(peerId);

  void lockPeer(String peerId) => _unlockedPeers.remove(peerId);
  void lockAll() {
    _unlockedPeers.clear();
    _appUnlocked = false;
  }

  Future<bool> hasPassword() => DatabaseService.instance.hasPassword();

  Future<void> setPassword(String password) =>
      DatabaseService.instance.setPassword(password);

  Future<bool> verify(String password) =>
      DatabaseService.instance.verifyPassword(password);

  void markAppUnlocked(String peerId) {
    _appUnlocked = true;
    _unlockedPeers.add(peerId);
  }
}

// Full-screen lock page. Returned value: true = unlocked, false = cancelled.
class LockScreen extends StatefulWidget {
  final String peerId;
  final bool isSetup; // true = first-time password creation

  const LockScreen({
    super.key,
    required this.peerId,
    this.isSetup = false,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _passwordController.text;
    if (pw.isEmpty) {
      setState(() => _error = '請輸入密碼');
      return;
    }

    setState(() { _loading = true; _error = null; });

    if (widget.isSetup) {
      if (pw != _confirmController.text) {
        setState(() { _loading = false; _error = '兩次密碼不一致'; });
        return;
      }
      await ChatSessionLock.instance.setPassword(pw);
      ChatSessionLock.instance.markAppUnlocked(widget.peerId);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      final ok = await ChatSessionLock.instance.verify(pw);
      if (ok) {
        ChatSessionLock.instance.markAppUnlocked(widget.peerId);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() { _loading = false; _error = '密碼錯誤，請再試一次'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 64, color: Colors.orange.shade600),
                const SizedBox(height: 24),
                Text(
                  widget.isSetup ? '設定聊天室密碼' : '輸入聊天室密碼',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isSetup
                      ? '此密碼保護所有加密聊天室，請妥善保存。'
                      : '輸入密碼以進入加密聊天室。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  onSubmitted: (_) =>
                      widget.isSetup ? FocusScope.of(context).nextFocus() : _submit(),
                  decoration: InputDecoration(
                    labelText: '密碼',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (widget.isSetup) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmController,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '確認密碼',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.isSetup ? '設定密碼' : '解鎖',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
