import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_info.dart';
import '../models/chat_message.dart';
import 'encryption_service.dart';
import 'media_service.dart';

class _PendingDelete {
  final DocumentReference ref;
  final String? cloudinaryPublicId;
  final String? mediaType;
  _PendingDelete(this.ref, {this.cloudinaryPublicId, this.mediaType});
}

class ChatService {
  final EncryptionService _encryptionService;
  final _mediaService = MediaService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _currentUser;
  String? _currentHandle;
  StreamSubscription? _messagesSub;
  String? _listeningPeerId;
  bool _disposed = false;

  final List<_PendingDelete> _pendingDeletes = [];
  final Map<String, String> _peerPublicKeys = {};

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  ChatService(this._encryptionService);

  String? get currentUserId => _currentUser?.uid;
  String? get currentHandle => _currentHandle;
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  Stream<Map<String, dynamic>> get burnAckStream => _eventController.stream;

  Future<void> initialize(User user) async {
    _currentUser = user;
    await _encryptionService.generateKeyPair();

    // Load existing doc to preserve userHandle
    final docSnap =
        await _firestore.collection('users').doc(user.uid).get();
    _currentHandle = docSnap.data()?['userHandle'] as String?;

    // If no handle yet, generate a default from UID
    if (_currentHandle == null || _currentHandle!.isEmpty) {
      final raw = user.uid.replaceAll(RegExp(r'[^a-z0-9]'), '');
      _currentHandle = 'u_${raw.substring(0, raw.length.clamp(0, 8))}';
    }

    await _firestore.collection('users').doc(user.uid).set({
      'displayName': user.displayName ?? user.email ?? 'Unknown',
      'photoURL': user.photoURL ?? '',
      'publicKey': _encryptionService.publicKeyBase64,
      'userHandle': _currentHandle,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Returns null on success, error message string on failure.
  Future<String?> updateHandle(String newHandle) async {
    final handle = newHandle.toLowerCase().trim();
    if (handle.length < 3) return '用戶 ID 至少需要 3 個字元';
    if (handle.length > 20) return '用戶 ID 最多 20 個字元';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(handle)) {
      return '只能使用英文小寫字母、數字與底線 (_)';
    }

    final snap = await _firestore
        .collection('users')
        .where('userHandle', isEqualTo: handle)
        .limit(1)
        .get();

    final taken =
        snap.docs.isNotEmpty && snap.docs.first.id != _currentUser!.uid;
    if (taken) return '此用戶 ID 已被使用，請換一個';

    await _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .update({'userHandle': handle});
    _currentHandle = handle;
    return null;
  }

  // Search a user by exact handle. Returns null if not found.
  Future<ChatUser?> searchUser(String handle) async {
    final snap = await _firestore
        .collection('users')
        .where('userHandle', isEqualTo: handle.toLowerCase().trim())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    if (d.id == _currentUser?.uid) return null; // can't chat with yourself
    final data = d.data();
    _peerPublicKeys[d.id] = data['publicKey'] as String? ?? '';
    return ChatUser(
      userId: d.id,
      displayName: data['displayName'] as String? ?? d.id,
      photoURL: data['photoURL'] as String? ?? '',
      publicKey: data['publicKey'] as String? ?? '',
      userHandle: data['userHandle'] as String? ?? '',
    );
  }

  String _chatId(String peerId) {
    final ids = [_currentUser!.uid, peerId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  void listenToMessages(String peerId) {
    if (_listeningPeerId == peerId) return;
    _listeningPeerId = peerId;
    _messagesSub?.cancel();
    _pendingDeletes.clear();

    _messagesSub = _firestore
        .collection('chats')
        .doc(_chatId(peerId))
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
            _processIncoming(change.doc, peerId);
          case DocumentChangeType.modified:
            _processModified(change.doc, peerId);
          case DocumentChangeType.removed:
            _handleRemoved(change.doc);
        }
      }
    });
  }

  Future<void> _processIncoming(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String peerId,
  ) async {
    try {
      final data = doc.data()!;
      final from = data['from'] as String;
      if (from == _currentUser!.uid) return;

      final burnTimer = data['burnTimer'] as String? ?? 'off';
      final cloudinaryPublicId = data['cloudinaryPublicId'] as String?;
      final rawMediaType = data['mediaType'] as String?;

      if (data['recalled'] == true) {
        if (!_messageController.isClosed) {
          _messageController.add(ChatMessage(
            documentId: doc.id,
            from: from,
            to: _currentUser!.uid,
            text: '',
            timestamp:
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            burnTimer: burnTimer,
            recalled: true,
            isSentByMe: false,
          ));
        }
        doc.reference.delete().catchError((_) {});
        return;
      }

      final publicKey = await _resolvePublicKey(from);
      if (publicKey.isEmpty) return;

      final sharedSecret =
          await _encryptionService.getSharedSecret(from, publicKey);
      final plainText =
          await _encryptionService.decryptFromMap(data, sharedSecret);
      final payload = jsonDecode(plainText) as Map<String, dynamic>;

      if (!_messageController.isClosed) {
        _messageController.add(ChatMessage(
          documentId: doc.id,
          from: from,
          to: _currentUser!.uid,
          text: payload['text'] as String? ?? '',
          mediaUrl: payload['mediaUrl'] as String?,
          mediaType: payload['mediaType'] as String?,
          fileName: payload['fileName'] as String?,
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          burnTimer: burnTimer,
          edited: data['edited'] as bool? ?? false,
          isSentByMe: false,
        ));
      }

      switch (burnTimer) {
        case '1m':
          Future.delayed(const Duration(minutes: 1), () =>
              _burnCloudinaryAndDoc(
                  doc.reference, cloudinaryPublicId, rawMediaType));
        case '3m':
          Future.delayed(const Duration(minutes: 3), () =>
              _burnCloudinaryAndDoc(
                  doc.reference, cloudinaryPublicId, rawMediaType));
        case '5m':
          Future.delayed(const Duration(minutes: 5), () =>
              _burnCloudinaryAndDoc(
                  doc.reference, cloudinaryPublicId, rawMediaType));
        default:
          _pendingDeletes.add(_PendingDelete(
            doc.reference,
            cloudinaryPublicId: cloudinaryPublicId,
            mediaType: rawMediaType,
          ));
      }
    } catch (_) {}
  }

  void _burnCloudinaryAndDoc(
    DocumentReference ref,
    String? publicId,
    String? mediaType,
  ) {
    if (publicId != null && mediaType != null) {
      final resourceType = mediaType == 'file' ? 'raw' : mediaType;
      _mediaService.delete(publicId, resourceType);
    }
    ref.delete().catchError((_) {});
  }

  Future<void> _processModified(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String peerId,
  ) async {
    try {
      final data = doc.data()!;
      final from = data['from'] as String;
      if (from == _currentUser!.uid) return;

      if (data['recalled'] == true) {
        if (!_eventController.isClosed) {
          _eventController.add({'type': 'recall', 'documentId': doc.id});
        }
        doc.reference.delete().catchError((_) {});
        return;
      }

      if (data['edited'] == true) {
        final publicKey = await _resolvePublicKey(from);
        if (publicKey.isEmpty) return;
        final sharedSecret =
            await _encryptionService.getSharedSecret(from, publicKey);
        final plainText =
            await _encryptionService.decryptFromMap(data, sharedSecret);
        final payload = jsonDecode(plainText) as Map<String, dynamic>;
        if (!_eventController.isClosed) {
          _eventController.add({
            'type': 'edit',
            'documentId': doc.id,
            'newText': payload['text'] as String,
          });
        }
      }
    } catch (_) {}
  }

  void _handleRemoved(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return;
    final burnTimer = data['burnTimer'] as String? ?? 'off';
    final msgFrom = data['from'] as String?;

    if (burnTimer != 'off' && msgFrom == _currentUser!.uid) {
      if (!_eventController.isClosed) {
        _eventController.add({
          'type': 'burn',
          'documentId': doc.id,
          'from': data['to'] as String? ?? '',
        });
      }
    }
  }

  Future<String> _resolvePublicKey(String uid) async {
    if (_peerPublicKeys[uid]?.isNotEmpty == true) return _peerPublicKeys[uid]!;
    final doc = await _firestore.collection('users').doc(uid).get();
    final pk = doc.data()?['publicKey'] as String? ?? '';
    _peerPublicKeys[uid] = pk;
    return pk;
  }

  Future<void> sendMessage(
    String peerId,
    String text, {
    String burnTimer = 'off',
    String? mediaUrl,
    String? mediaType,
    String? fileName,
    String? cloudinaryPublicId,
  }) async {
    final publicKey = await _resolvePublicKey(peerId);
    if (publicKey.isEmpty) return;

    final sharedSecret =
        await _encryptionService.getSharedSecret(peerId, publicKey);
    final plainPayload = jsonEncode({
      'text': text,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'fileName': fileName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final encrypted =
        await _encryptionService.encryptToMap(plainPayload, sharedSecret);

    final docRef = await _firestore
        .collection('chats')
        .doc(_chatId(peerId))
        .collection('messages')
        .add({
      'from': _currentUser!.uid,
      'to': peerId,
      ...encrypted,
      'burnTimer': burnTimer,
      'mediaType': mediaType,
      'cloudinaryPublicId': cloudinaryPublicId,
      'fileName': fileName,
      'recalled': false,
      'edited': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!_messageController.isClosed) {
      _messageController.add(ChatMessage(
        documentId: docRef.id,
        from: _currentUser!.uid,
        to: peerId,
        text: text,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        fileName: fileName,
        timestamp: DateTime.now(),
        burnTimer: burnTimer,
        isSentByMe: true,
      ));
    }
  }

  Future<void> editMessage(
      String documentId, String peerId, String newText) async {
    final publicKey = await _resolvePublicKey(peerId);
    if (publicKey.isEmpty) return;

    final sharedSecret =
        await _encryptionService.getSharedSecret(peerId, publicKey);
    final plainPayload = jsonEncode({
      'text': newText,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final encrypted =
        await _encryptionService.encryptToMap(plainPayload, sharedSecret);

    await _firestore
        .collection('chats')
        .doc(_chatId(peerId))
        .collection('messages')
        .doc(documentId)
        .update({...encrypted, 'edited': true});

    if (!_eventController.isClosed) {
      _eventController.add({
        'type': 'edit',
        'documentId': documentId,
        'newText': newText,
      });
    }
  }

  Future<void> recallMessage(String documentId, String peerId) async {
    await _firestore
        .collection('chats')
        .doc(_chatId(peerId))
        .collection('messages')
        .doc(documentId)
        .update({'recalled': true, 'ct': '', 'nonce': '', 'mac': ''});

    if (!_eventController.isClosed) {
      _eventController.add({'type': 'recall', 'documentId': documentId});
    }
  }

  void stopListening() {
    for (final pending in _pendingDeletes) {
      _burnCloudinaryAndDoc(
        pending.ref,
        pending.cloudinaryPublicId,
        pending.mediaType,
      );
    }
    _pendingDeletes.clear();
    _messagesSub?.cancel();
    _listeningPeerId = null;
  }

  Future<void> burnMessage(String documentId, String peerId) async {}

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopListening();
    _messageController.close();
    _eventController.close();
  }
}
