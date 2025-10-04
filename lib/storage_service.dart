import 'dart:html' as html;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

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
    html.window.localStorage['${_keyPrefix}wallet'] = encrypted;
  }

  // Load wallet (decrypt)
  String? loadWallet(String password) {
    final encrypted = html.window.localStorage['${_keyPrefix}wallet'];
    if (encrypted == null) return null;

    try {
      return _decrypt(encrypted, password);
    } catch (e) {
      return null;
    }
  }

  // Check if wallet exists
  bool hasWallet() {
    return html.window.localStorage['${_keyPrefix}wallet'] != null;
  }

  // Delete wallet
  void deleteWallet() {
    html.window.localStorage.remove('${_keyPrefix}wallet');
  }

  // Save RPC config
  void saveRpcConfig(String url, String user, String password) {
    final config = jsonEncode({
      'url': url,
      'user': user,
      'password': password,
    });
    html.window.localStorage['${_keyPrefix}rpc'] = config;
  }

  // Load RPC config
  Map<String, String>? loadRpcConfig() {
    final config = html.window.localStorage['${_keyPrefix}rpc'];
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
    html.window.sessionStorage['${_keyPrefix}session'] = privateKey;
  }

  String? loadSession() {
    return html.window.sessionStorage['${_keyPrefix}session'];
  }

  void clearSession() {
    html.window.sessionStorage.remove('${_keyPrefix}session');
  }
}
