import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:bech32/bech32.dart';
import 'package:base_x/base_x.dart';

class WalletService {
  final BaseXCodec base58 = BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');

  static const String addressPrefix = 'bs';
  static const int networkPrefix = 0x80;

  // Generate a new wallet
  Map<String, String> generateNewWallet() {
    final random = Random.secure();
    final privateKeyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      privateKeyBytes[i] = random.nextInt(256);
    }

    final wif = _privateKeyToWif(privateKeyBytes);
    final address = getAddressFromWif(wif);

    return {
      'privateKey': wif,
      'address': address ?? '',
    };
  }

  // Convert private key to WIF
  String _privateKeyToWif(Uint8List privateKey) {
    final extended = Uint8List(1 + privateKey.length + 1);
    extended[0] = networkPrefix;
    extended.setRange(1, 1 + privateKey.length, privateKey);
    extended[extended.length - 1] = 0x01; // Compressed flag

    final checksum = _calculateChecksum(extended);
    final withChecksum = Uint8List(extended.length + checksum.length);
    withChecksum.setRange(0, extended.length, extended);
    withChecksum.setRange(extended.length, withChecksum.length, checksum);

    return base58.encode(withChecksum);
  }

  // Get address from WIF private key
  String? getAddressFromWif(String wifPrivateKey) {
    try {
      final privateKey = _wifToPrivateKey(wifPrivateKey);
      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));
      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);
      return _encodeBech32Address(addressPrefix, 0, pubKeyHash);
    } catch (e) {
      return null;
    }
  }

  Uint8List _wifToPrivateKey(String wif) {
    final bytes = base58.decode(wif);
    final keyWithChecksum = bytes.sublist(0, bytes.length - 4);
    final checksum = bytes.sublist(bytes.length - 4);

    final calculatedChecksum = _calculateChecksum(keyWithChecksum);
    if (!_listEquals(checksum, calculatedChecksum)) {
      throw Exception('Invalid WIF checksum');
    }

    return Uint8List.fromList(keyWithChecksum.sublist(
        1, keyWithChecksum.length - (keyWithChecksum.length > 32 ? 1 : 0)));
  }

  Uint8List _calculateChecksum(Uint8List data) {
    final sha256_1 = sha256.convert(data).bytes;
    final sha256_2 = sha256.convert(Uint8List.fromList(sha256_1)).bytes;
    return Uint8List.fromList(sha256_2.sublist(0, 4));
  }

  Uint8List _pubKeyToP2WPKH(List<int> pubKey) {
    final sha256Hash = sha256.convert(pubKey).bytes;
    final ripemd160Hash = RIPEMD160Digest().process(Uint8List.fromList(sha256Hash));
    return Uint8List.fromList(ripemd160Hash);
  }

  String _encodeBech32Address(String hrp, int version, Uint8List program) {
    final converted = _convertBits(program, 8, 5, true);
    final data = [version] + converted;
    return const Bech32Codec().encode(Bech32(hrp, data));
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0, bits = 0;
    final ret = <int>[];
    final maxv = (1 << to) - 1;

    for (final value in data) {
      if (value < 0 || (value >> from) != 0) throw Exception('Invalid value');
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        ret.add((acc >> bits) & maxv);
      }
    }

    if (pad && bits > 0) ret.add((acc << (to - bits)) & maxv);
    if (!pad && (bits >= from || ((acc << (to - bits)) & maxv) != 0)) {
      throw Exception('Invalid padding');
    }
    return ret;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // RPC calls
  Future<Map<String, dynamic>?> rpcRequest(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
    String method,
    [List<dynamic>? params]
  ) async {
    final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
    final headers = {'Content-Type': 'application/json', 'Authorization': auth};

    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': 'web',
      'method': method,
      'params': params ?? [],
    });

    try {
      final response = await http.post(
        Uri.parse(rpcUrl),
        headers: headers,
        body: body,
      );

      return jsonDecode(response.body);
    } catch (e) {
      return null;
    }
  }

  // Get UTXOs for address
  Future<List<Map<String, dynamic>>> getUtxos(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
    String address,
  ) async {
    final result = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'scantxoutset', [
      'start',
      [{'desc': 'addr($address)'}]
    ]);

    if (result == null || result['result'] == null) return [];

    final utxos = result['result']['unspents'] as List<dynamic>? ?? [];

    // Get blockchain height for confirmations
    final blockchainInfo = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getblockchaininfo');
    final currentHeight = blockchainInfo?['result']?['blocks'] ?? 0;

    return utxos.map((utxo) {
      int confirmations = 0;
      if (utxo['height'] != null && utxo['height'] > 0) {
        confirmations = currentHeight - utxo['height'] + 1;
      }
      return {
        ...utxo as Map<String, dynamic>,
        'confirmations': confirmations,
      };
    }).where((utxo) => utxo['confirmations'] > 0).toList();
  }

  // Send transaction
  Future<Map<String, dynamic>> sendTransaction(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
    String privateKeyWif,
    String fromAddress,
    String toAddress,
    double amount,
  ) async {
    // Get UTXOs
    final utxos = await getUtxos(rpcUrl, rpcUser, rpcPassword, fromAddress);

    if (utxos.isEmpty) {
      return {'success': false, 'message': 'No confirmed UTXOs available'};
    }

    // Sort by amount (largest first)
    utxos.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    // Select UTXOs
    List<Map<String, dynamic>> selectedUtxos = [];
    double inputSum = 0.0;
    const double feeRate = 0.00001;

    for (var utxo in utxos) {
      selectedUtxos.add({'txid': utxo['txid'], 'vout': utxo['vout']});
      inputSum += utxo['amount'];

      final inputCount = selectedUtxos.length;
      final outputCount = 2;
      final txSize = 10 + (inputCount * 148) + (outputCount * 34);
      final fee = (feeRate * txSize / 1000);

      if (inputSum >= amount + fee) {
        final actualFee = double.parse(fee.toStringAsFixed(8));
        final change = double.parse((inputSum - amount - actualFee).toStringAsFixed(8));

        final outputs = <String, dynamic>{
          toAddress: double.parse(amount.toStringAsFixed(8)),
        };

        if (change > 0.00000546) {
          outputs[fromAddress] = change;
        }

        // Create raw transaction
        final createResult = await rpcRequest(
          rpcUrl, rpcUser, rpcPassword,
          'createrawtransaction',
          [selectedUtxos, outputs]
        );

        if (createResult == null || createResult['result'] == null) {
          return {'success': false, 'message': 'Failed to create transaction'};
        }

        // Sign transaction
        final signResult = await rpcRequest(
          rpcUrl, rpcUser, rpcPassword,
          'signrawtransactionwithkey',
          [createResult['result'], [privateKeyWif]]
        );

        if (signResult == null || signResult['result'] == null) {
          return {'success': false, 'message': 'Failed to sign transaction'};
        }

        if (!signResult['result']['complete']) {
          return {'success': false, 'message': 'Transaction signature incomplete'};
        }

        // Send transaction
        final sendResult = await rpcRequest(
          rpcUrl, rpcUser, rpcPassword,
          'sendrawtransaction',
          [signResult['result']['hex'], 0]
        );

        if (sendResult != null && sendResult['result'] != null) {
          return {
            'success': true,
            'txid': sendResult['result'],
            'fee': actualFee,
          };
        }

        final errorMessage = sendResult?['error']?['message'] ?? 'Unknown error';
        return {'success': false, 'message': errorMessage};
      }
    }

    return {
      'success': false,
      'message': 'Insufficient funds. Available: ${inputSum.toStringAsFixed(8)} BTCS'
    };
  }

  // Calculate balance from UTXOs
  double calculateBalance(List<Map<String, dynamic>> utxos) {
    return utxos.fold(0.0, (sum, utxo) => sum + (utxo['amount'] as double? ?? 0.0));
  }
}
