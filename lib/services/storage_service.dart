import 'package:web/web.dart' as web;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class StorageService {
  static const String _keyPrefix = 'btcs_';
  static const String _persistentSessionKey = '${_keyPrefix}persistent_session';
  static const String _persistentSessionEnabledKey = '${_keyPrefix}persistent_session_enabled';
  static const String _legalDisclaimerAcceptedKey = '${_keyPrefix}legal_disclaimer_accepted';

  // Simple AES-like encryption using XOR with password hash
  String _encrypt(String data, String password) {
    final passwordHash = sha256.convert(utf8.encode(password)).bytes;
    final dataBytes = utf8.encode(data);
    final encrypted = <int>[];

    for (int i = 0; i < dataBytes.length; i++) {
      encrypted.add(dataBytes[i] ^ passwordHash[i % passwordHash.length]);
    }

    return base64Encode(encrypted);
  }

  String _decrypt(String encryptedData, String password) {
    final passwordHash = sha256.convert(utf8.encode(password)).bytes;
    final encrypted = base64Decode(encryptedData);
    final decrypted = <int>[];

    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ passwordHash[i % passwordHash.length]);
    }

    return utf8.decode(decrypted);
  }

  // Save wallet (encrypted)
  void saveWallet(String privateKey, String password) {
    final encrypted = _encrypt(privateKey, password);
    web.window.localStorage.setItem('${_keyPrefix}wallet', encrypted);
  }

  // Load wallet (decrypt)
  String? loadWallet(String password) {
    final encrypted = web.window.localStorage.getItem('${_keyPrefix}wallet');
    if (encrypted == null) return null;

    try {
      return _decrypt(encrypted, password);
    } catch (e) {
      return null;
    }
  }

  // Check if wallet exists
  bool hasWallet() {
    return web.window.localStorage.getItem('${_keyPrefix}wallet') != null;
  }

  // Delete wallet
  void deleteWallet() {
    web.window.localStorage.removeItem('${_keyPrefix}wallet');
  }

  // Save RPC config
  void saveRpcConfig(String url, String user, String password) {
    final config = jsonEncode({
      'url': url,
      'user': user,
      'password': password,
    });
    web.window.localStorage.setItem('${_keyPrefix}rpc', config);
  }

  // Load RPC config
  Map<String, String>? loadRpcConfig() {
    final config = web.window.localStorage.getItem('${_keyPrefix}rpc');
    if (config == null) return null;

    try {
      final decoded = jsonDecode(config) as Map<String, dynamic>;
      return {
        'url': decoded['url'] as String,
        'user': decoded['user'] as String,
        'password': decoded['password'] as String,
      };
    } catch (e) {
      return null;
    }
  }

  // Session storage (cleared when browser closes)
  void saveSession(String privateKey) {
    web.window.sessionStorage.setItem('${_keyPrefix}session', privateKey);
  }

  String? loadSession() {
    return web.window.sessionStorage.getItem('${_keyPrefix}session');
  }

  void clearSession() {
    web.window.sessionStorage.removeItem('${_keyPrefix}session');
  }

  void savePersistentSessionEnabled(bool enabled) {
    web.window.localStorage
        .setItem(_persistentSessionEnabledKey, enabled ? '1' : '0');
  }

  bool loadPersistentSessionEnabled() {
    return web.window.localStorage.getItem(_persistentSessionEnabledKey) == '1';
  }

  bool hasPersistentSession() {
    final value = web.window.localStorage.getItem(_persistentSessionKey);
    return value != null && value.isNotEmpty;
  }

  void clearLegalDisclaimerAccepted() {
    web.window.localStorage.removeItem(_legalDisclaimerAcceptedKey);
  }

  bool savePersistentSession(
    Map<String, dynamic> payload,
    String secretHex,
  ) {
    final encoded = jsonEncode(payload);
    final encrypted = _encryptWithSecret(encoded, secretHex);
    if (encrypted == null) return false;
    web.window.localStorage.setItem(_persistentSessionKey, encrypted);
    return true;
  }

  Map<String, dynamic>? loadPersistentSession(String secretHex) {
    final encrypted = web.window.localStorage.getItem(_persistentSessionKey);
    if (encrypted == null || encrypted.isEmpty) return null;
    final decrypted = _decryptWithSecret(encrypted, secretHex);
    if (decrypted == null) return null;

    try {
      final dynamic decoded = jsonDecode(decrypted);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  void clearPersistentSession() {
    web.window.localStorage.removeItem(_persistentSessionKey);
  }

  bool _isValidSecretHex(String secretHex) {
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(secretHex);
  }

  Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      out[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  String? _encryptWithSecret(String plaintext, String secretHex) {
    if (!_isValidSecretHex(secretHex)) return null;

    try {
      final key = _hexToBytes(secretHex);
      final nonce = Uint8List(12);
      final rng = Random.secure();
      for (int i = 0; i < nonce.length; i++) {
        nonce[i] = rng.nextInt(256);
      }

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
        );

      final input = Uint8List.fromList(utf8.encode(plaintext));
      final output = Uint8List(cipher.getOutputSize(input.length));
        final processed = cipher.processBytes(input, 0, input.length, output, 0);
        final len = processed + cipher.doFinal(output, processed);

      final payload = jsonEncode({
        'v': 1,
        'n': base64Encode(nonce),
        'c': base64Encode(output.sublist(0, len)),
      });

      return payload;
    } catch (_) {
      return null;
    }
  }

  String? _decryptWithSecret(String encryptedPayload, String secretHex) {
    if (!_isValidSecretHex(secretHex)) return null;

    try {
      final dynamic decoded = jsonDecode(encryptedPayload);
      if (decoded is! Map<String, dynamic>) return null;
      final nonceRaw = decoded['n'] as String?;
      final cipherRaw = decoded['c'] as String?;
      if (nonceRaw == null || cipherRaw == null) return null;

      final key = _hexToBytes(secretHex);
      final nonce = base64Decode(nonceRaw);
      final ciphertext = base64Decode(cipherRaw);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), 128, Uint8List.fromList(nonce), Uint8List(0)),
        );

      final output = Uint8List(cipher.getOutputSize(ciphertext.length));
        final processed =
          cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
        final len = processed + cipher.doFinal(output, processed);

      return utf8.decode(output.sublist(0, len));
    } catch (_) {
      return null;
    }
  }
}
