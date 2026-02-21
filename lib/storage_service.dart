import 'package:web/web.dart' as web;
import 'dart:convert';
import 'package:crypto/crypto.dart';

class StorageService {
  static const String _keyPrefix = 'btcs_';

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
}
