import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;
  final Map<String, SecretKey> _sharedSecrets = {};

  final x25519 = X25519();
  final aesGcm = AesGcm.with256bits();

  Future<void> generateKeyPair() async {
    _keyPair = await x25519.newKeyPair();
    _publicKey = await _keyPair!.extractPublicKey();
  }

  String get publicKeyBase64 => base64Encode(_publicKey!.bytes);

  Future<SecretKey> getSharedSecret(String peerId, String peerPublicKeyBase64) async {
    if (_sharedSecrets.containsKey(peerId)) {
      return _sharedSecrets[peerId]!;
    }
    final remoteKey = SimplePublicKey(
      base64Decode(peerPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final secret = await x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remoteKey,
    );
    _sharedSecrets[peerId] = secret;
    return secret;
  }

  Future<Map<String, String>> encryptToMap(String plainText, SecretKey sharedSecret) async {
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: sharedSecret,
    );
    return {
      'ct': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String> decryptFromMap(Map<String, dynamic> data, SecretKey sharedSecret) async {
    final secretBox = SecretBox(
      base64Decode(data['ct'] as String),
      nonce: base64Decode(data['nonce'] as String),
      mac: Mac(base64Decode(data['mac'] as String)),
    );
    final plainBytes = await aesGcm.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );
    return utf8.decode(plainBytes);
  }

  void clearSharedSecret(String peerId) {
    _sharedSecrets.remove(peerId);
  }
}
