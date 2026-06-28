import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:bech32/bech32.dart';
import 'package:base_x/base_x.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:hex/hex.dart';
import '../services/btcs_signer.dart';

class WalletService {
  final BaseXCodec base58 = BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');

  static const String addressPrefix = 'bs';
  static const int networkPrefix = 0x80; // 128 in decimal, for mainnet WIF

  // Generate a new wallet
  Map<String, String> generateNewWallet() {
    final random = Random.secure();
    final privateKeyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      privateKeyBytes[i] = random.nextInt(256);
    }

    final wif = privateKeyToWif(privateKeyBytes);
    final address = getAddressFromWif(wif);

      return {
        'privateKey': wif,
        'address': address ?? '',
      };
    }

    // Generate a new Seed Phrase wallet
    Future<Map<String, String>> generateNewSeedWallet({int words = 12}) async {
    final int strength = words == 24 ? 256 : 128;
    final mnemonic = bip39.generateMnemonic(strength: strength);
    return (await getWalletFromMnemonic(mnemonic))!;
    }

    Future<Map<String, String>?> getWalletFromMnemonic(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic)) return null;

    final seed = await bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    final child = root.derivePath("m/44'/0'/0'/0/0");
    final privateKey = child.privateKey!;

    final wif = privateKeyToWif(privateKey);
    final address = getAddressFromWif(wif);

    return {
      'mnemonic': mnemonic,
      'privateKey': wif,
      'address': address ?? '',
    };
  }

  // Convert private key to WIF
  String privateKeyToWif(Uint8List privateKey) {
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
      final privateKey = wifToPrivateKey(wifPrivateKey);
      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));

      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);
      return _encodeBech32Address(addressPrefix, 0, pubKeyHash);
    } catch (e) {
      return null;
    }
  }

  Uint8List wifToPrivateKey(String wif) {
    final bytes = base58.decode(wif);
    final keyWithChecksum = bytes.sublist(0, bytes.length - 4);
    final checksum = bytes.sublist(bytes.length - 4);

    final calculatedChecksum = _calculateChecksum(keyWithChecksum);
    if (!_listEquals(checksum, calculatedChecksum)) {
      throw Exception('Invalid WIF checksum');
    }

    if (keyWithChecksum[0] != networkPrefix) {
      throw Exception('Incompatible WIF prefix: 0x${keyWithChecksum[0].toRadixString(16).toUpperCase()}. BTCS uses 0x${networkPrefix.toRadixString(16).toUpperCase()} (Check your WIF prefix and ensure you are using a compatible wallet).');
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
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (rpcUser.isNotEmpty || rpcPassword.isNotEmpty) {
      final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
      headers['Authorization'] = auth;
    }

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

      // 🛑 CRITICAL GATE: If it's a 404, 500, or HTML error page, do not parse it.
      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP status code: ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      
      // Safety check to ensure the decoded object is a proper JSON-RPC response map
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      
      throw Exception('Invalid RPC response format received');
    } catch (e) {
      // 🚨 CRITICAL: Do NOT return null. Rethrow the error so that upper layers
      // (like _isRpcAvailable or try-catch blocks) know the connection is dead!
      rethrow;
    }
  }

  // Get UTXOs for address
  Future<List<Map<String, dynamic>>> getUtxos(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
    String address,
  ) async {
    // 1. Get confirmed UTXOs from the chain
    final result = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'scantxoutset', [
      'start',
      [{'desc': 'addr($address)'}]
    ]);

    // Fetch current block height
    int currentHeight = 0;
    final blockCountResult = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getblockcount');
    if (blockCountResult != null && blockCountResult['result'] != null) {
      currentHeight = (blockCountResult['result'] as num).toInt();
    }

    final List<Map<String, dynamic>> confirmedUtxos = [];
    if (result != null && result['result'] != null) {
      final unspents = result['result']['unspents'] as List<dynamic>? ?? [];
      for (var u in unspents) {
        final int utxoHeight = (u['height'] as num).toInt();
        final int conf = currentHeight > 0 && utxoHeight > 0
            ? currentHeight - utxoHeight + 1
            : 1;
        confirmedUtxos.add({
          'txid': u['txid'],
          'vout': u['vout'],
          'amount': (u['amount'] is num) ? (u['amount'] as num).toDouble() : double.tryParse(u['amount'].toString()) ?? 0.0,
          'height': utxoHeight,
          'confirmations': conf,
        });
      }
    }

    // 2. Get mempool txids (try RPC first, fallback to Explorer API)
    final List<Map<String, dynamic>> decodedMempool = [];
    bool rpcMempoolSucceeded = false;
    final mempoolResult = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getrawmempool', [false]);
    
    if (mempoolResult != null && mempoolResult['result'] != null) {
      rpcMempoolSucceeded = true;
      final List<dynamic> txids = mempoolResult['result'] as List<dynamic>;
      for (var txid in txids) {
        final rawTx = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getrawtransaction', [txid, true]);
        if (rawTx != null && rawTx['result'] != null) {
          decodedMempool.add(rawTx['result'] as Map<String, dynamic>);
        }
      }
    }

    // Fallback: ONLY if RPC failed (not if mempool was just empty)
    if (!rpcMempoolSucceeded) {
      try {
        final explorerResponse = await http.get(Uri.parse('https://explorer.bitcoinsilver.top/api/mempool'));
        if (explorerResponse.statusCode == 200) {
          final List<dynamic> explorerTxs = jsonDecode(explorerResponse.body)['transactions'];
          for (var tx in explorerTxs) {
            decodedMempool.add(tx as Map<String, dynamic>);
          }
        }
      } catch (_) {}
    }

    final List<Map<String, dynamic>> finalUtxos = [];
    bool hasMempoolActivity = false;

    // 3. Process Decoded Mempool (Detect spends and incoming)
    final spentInMempool = <String>{};
    final incomingFromMempool = <Map<String, dynamic>>[];

    for (var data in decodedMempool) {
      final String txid = data['txid'] ?? '';
      
      // Check inputs (detect our coins being spent)
      final vins = data['vin'] as List<dynamic>? ?? [];
      for (var vin in vins) {
        // Handle both RPC (txid/vout) and Explorer (prev_txid/prev_vout or similar) formats
        final String? vinTxid = vin['txid'] ?? vin['prev_txid'];
        final dynamic vinVout = vin['vout'] ?? vin['prev_vout'];
        if (vinTxid != null && vinVout != null) {
          spentInMempool.add('$vinTxid:$vinVout');
        }
      }

      // Check outputs (detect new funds or change)
      final vouts = data['vout'] as List<dynamic>? ?? [];
      for (var vout in vouts) {
        final scriptPubKey = vout['scriptPubKey'] as Map<String, dynamic>? ?? {};
        final addresses = scriptPubKey['addresses'] as List<dynamic>? ?? [];
        final String? singleAddr = scriptPubKey['address'] as String?;
        
        if (addresses.contains(address) || (singleAddr != null && singleAddr == address)) {
          // --- Safe Numeric Parsing ---
          double parsedAmount = 0.0;
          final rawValue = vout['value'];
          if (rawValue is num) {
            parsedAmount = rawValue.toDouble();
          } else if (rawValue is String) {
            parsedAmount = double.tryParse(rawValue) ?? 0.0;
          }
          incomingFromMempool.add({
            'txid': txid,
            'vout': vout['n'] ?? 0,
            'amount': parsedAmount, // Safely parsed amount
            'confirmations': 0,
          });
          hasMempoolActivity = true;
        }
      }
    }

    // 4. Merge Confirmed and Mempool
    for (var utxo in confirmedUtxos) {
      final outpoint = '${utxo['txid']}:${utxo['vout']}';
      if (spentInMempool.contains(outpoint)) {
        hasMempoolActivity = true; // Flag that a confirmed coin is being spent
      } else {
        finalUtxos.add(utxo);
      }
    }
    finalUtxos.addAll(incomingFromMempool);

    // 5. Final Force-Yellow logic
    if (hasMempoolActivity && !finalUtxos.any((u) => u['confirmations'] == 0)) {
      finalUtxos.add({
        'txid': 'pending_marker',
        'amount': 0.0,
        'confirmations': 0,
      });
    }

    return finalUtxos;
  }

  // Send transaction
  Future<Map<String, dynamic>> resolveFeeRate(
    String rpcUrl,
    String rpcUser,
    String rpcPassword, {
    double? manualFeeRateCoinPerKb,
  }) async {
    if (manualFeeRateCoinPerKb != null) {
      if (manualFeeRateCoinPerKb <= 0) {
        return {
          'success': false,
          'message': 'Manual fee rate must be greater than zero.',
          'reason': 'invalid-manual-fee',
        };
      }
      return {
        'success': true,
        'feeRate': manualFeeRateCoinPerKb,
        'source': 'manual',
      };
    }

    try {
      final response = await rpcRequest(
        rpcUrl,
        rpcUser,
        rpcPassword,
        'estimatesmartfee',
        [6],
      );

      if (response?['error'] != null) {
        return {
          'success': false,
          'message': 'Node failed to estimate fee. Please enter a manual fee rate.',
          'reason': 'rpc-error',
        };
      }

      final dynamic rawFeeRate = response?['result']?['feerate'];
      final num? parsed = rawFeeRate is num ? rawFeeRate : num.tryParse(rawFeeRate?.toString() ?? '');
      final double? feeRate = parsed?.toDouble();

      if (feeRate == null || feeRate <= 0) {
        return {
          'success': false,
          'message': 'Node could not estimate fee (feerate unavailable or -1). Enter a manual fee rate.',
          'reason': 'no-estimate',
        };
      }

      return {
        'success': true,
        'feeRate': feeRate,
        'source': 'estimated',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Fee estimation request failed. Enter a manual fee rate.',
        'reason': 'request-failed',
      };
    }
  }

  Future<Map<String, dynamic>> sendTransaction(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
    String privateKeyWif,
    String fromAddress,
    String toAddress,
    double amount, {
    double? manualFeeRateCoinPerKb,
    List<Map<String, dynamic>>? preSelectedUtxos,
  }) async {
    // ── 1. Get UTXOs ────────────────────────────────────────────────────────
    final allUtxos = await getUtxos(rpcUrl, rpcUser, rpcPassword, fromAddress);
    final utxos = (preSelectedUtxos != null && preSelectedUtxos.isNotEmpty)
        ? preSelectedUtxos
        : allUtxos
            .where((u) =>
                u['txid'] != 'pending_marker' &&
                (u['confirmations'] as int) > 0)
            .toList();

    if (utxos.isEmpty) {
      final hasPending = allUtxos.any((u) =>
          u['txid'] != 'pending_marker' && (u['confirmations'] as int) == 0);
      return {
        'success': false,
        'message': hasPending
            ? 'Your funds are pending confirmation. Please wait approximately 10 minutes before sending again.'
            : 'No confirmed funds available. Please wait approximately 10 minutes for your deposit to confirm.',
      };
    }
    // ── 2. Ensure every UTXO has a scriptPubKey UP FRONT ────────────────────
    for (final utxo in utxos) {
      if (utxo['scriptPubKey'] == null || (utxo['scriptPubKey'] as String).isEmpty) {
        try {
          final txOut = await rpcRequest(
            rpcUrl, rpcUser, rpcPassword,
            'gettxout',
            [utxo['txid'], utxo['vout']],
          );
          if (txOut?['result']?['scriptPubKey']?['hex'] != null) {
            utxo['scriptPubKey'] = txOut!['result']['scriptPubKey']['hex'] as String;
          }
        } catch (_) {}
      }
      
      // Fallback directly to script generation from address if RPC fails
      if (utxo['scriptPubKey'] == null || (utxo['scriptPubKey'] as String).isEmpty) {
        try {
          final generatedScript = BTCSSigner.scriptFromAddress(fromAddress);
          utxo['scriptPubKey'] = HEX.encode(generatedScript);
        } catch (_) {
          return {
            'success': false,
            'message': 'Could not resolve scriptPubKey for UTXO ${utxo['txid']}.',
          };
        }
      }
    }

    final totalAvailable = utxos.fold(
        0.0, (sum, u) => sum + (u['amount'] as num).toDouble());
    final bool isSweep = amount >= totalAvailable - 0.00001;

    // Sort largest-first for efficient UTXO selection
    utxos.sort((a, b) => ((b['amount'] as num).toDouble())
        .compareTo((a['amount'] as num).toDouble()));

    // ── 3. Resolve fee rate (estimated or manual) ───────────────────────────
    final feeResolution = await resolveFeeRate(
      rpcUrl,
      rpcUser,
      rpcPassword,
      manualFeeRateCoinPerKb: manualFeeRateCoinPerKb,
    );

    if (feeResolution['success'] != true) {
      return {
        'success': false,
        'requiresManualFee': manualFeeRateCoinPerKb == null,
        'feeEstimationFailed': true,
        'message': feeResolution['message'] as String? ?? 'Unable to establish transaction fee.',
      };
    }

    final double feeRate = (feeResolution['feeRate'] as num).toDouble();
    final bool feeEstablished = feeRate > 0;

    // ── 4. UTXO selection + sizing loop ─────────────────────────────────────
    final selectedUtxos = <Map<String, dynamic>>[];
    double inputSum = 0.0;
    for (int i = 0; i < utxos.length; i++) {
      selectedUtxos.add(utxos[i]);
      inputSum += (utxos[i]['amount'] as num).toDouble();

      if (isSweep && i < utxos.length - 1) continue; 

      // Precise sizing depending on destination type
      final inputCount = selectedUtxos.length;
      final bool isDestLegacy = !toAddress.toLowerCase().startsWith('s2');
      
      // Legacy outputs are 34 bytes, Native SegWit outputs are 31 bytes.
      // Change address is always SegWit (31).
      final int destOutputSize = isDestLegacy ? 34 : 31;
      final int changeOutputSize = 31; 
      
      int txSize = 11 + (inputCount * 68);
      
      if (isSweep) {
        txSize += destOutputSize;
      } else {
        txSize += destOutputSize + changeOutputSize;
      }

      final actualFee = double.parse((feeRate * txSize / 1000).toStringAsFixed(8));
      final needed = isSweep ? actualFee : amount + actualFee;
      if (inputSum < needed) continue; // Loop until input matches costs

      // ── Build BTCSTxInput list ─────────────────────────────────────────
      final inputs = selectedUtxos.map((u) {
        String? scriptHex = u['scriptPubKey'] as String?;
      // Safety Checkpoint: If null or empty, compute it directly from the source address
        if (scriptHex == null || scriptHex.isEmpty) {
          try {
            final computedScript = BTCSSigner.scriptFromAddress(fromAddress);
            scriptHex = HEX.encode(computedScript);
          } catch (e) {
            scriptHex = ''; 
          }
        }
        return BTCSTxInput(
          txid: u['txid'] as String,
          vout: u['vout'] as int,
          scriptPubKey: Uint8List.fromList(HEX.decode(scriptHex)),
          satoshis: ((u['amount'] as num).toDouble() * 1e8).round(),
        );
      }).toList();

      // ── Build BTCSTxOutput list ────────────────────────────────────────
      final outputs = <BTCSTxOutput>[];
      try {
        if (isSweep) {
          final sweepSats = ((inputSum - actualFee) * 1e8).round();
          if (sweepSats <= 546) {
            return {'success': false, 'message': 'Balance too low to cover fees.'};
          }
          outputs.add(BTCSTxOutput(
            scriptPubKey: BTCSSigner.scriptFromAddress(toAddress),
            satoshis: sweepSats,
          ));
        } else {
          outputs.add(BTCSTxOutput(
            scriptPubKey: BTCSSigner.scriptFromAddress(toAddress),
            satoshis: (amount * 1e8).round(),
          ));
          final changeSats = ((inputSum - amount - actualFee) * 1e8).round();
          if (changeSats > 546) {
            outputs.add(BTCSTxOutput(
              scriptPubKey: BTCSSigner.scriptFromAddress(fromAddress),
              satoshis: changeSats,
            ));
          }
        }
      } catch (e) {
        return {'success': false, 'message': 'Invalid destination address provided.'};
      }

      // ── Sign locally ───────────────────────────────────────────────────
      String signedHex;
      try {
        signedHex = BTCSSigner.signTransaction(
          inputs: inputs,
          outputs: outputs,
          wif: privateKeyWif,
        );
      } catch (e) {
        return {'success': false, 'message': 'Signing failed: $e'};
      }

      // ── Broadcast ───────────────────────────────────────────────────────
      final sendResult = await rpcRequest(
        rpcUrl, rpcUser, rpcPassword,
        'sendrawtransaction',
        [signedHex], // Clean array input parameters
      );

      if (sendResult?['result'] != null) {
        return {
          'success': true,
          'txid': sendResult!['result'],
          'fee': actualFee,
        };
      }

      final errMsg = sendResult?['error']?['message'] as String? ?? 'Unknown error';
      if (feeEstablished &&
          (errMsg.contains('insufficient fee') || errMsg.contains('rejecting replacement'))) {
        return {
          'success': false,
          'message': 'You have a pending transaction. Please wait approximately 20 minutes before sending another.',
        };
      }
      return {'success': false, 'message': errMsg};
    }

    return {
      'success': false,
      'message': 'Insufficient funds. Available: ${inputSum.toStringAsFixed(8)} BTCS.',
    };
  }

  // ---------------------------------------------------------------------------
  // Get transaction history for an address via the Explorer API.
  // Uses server-side pagination with offset and limit.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getTransactions(String address, {int offset = 0, int limit = 10}) async {
    const String explorerBase = 'https://explorer.bitcoinsilver.top/api/getaddress';
    final url = '$explorerBase/$address/txs?offset=$offset&limit=$limit';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return {'transactions': [], 'txCount': 0};

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final txList = decoded['transactions'] as List<dynamic>? ?? [];
      final txCount = decoded['txCount'] as int? ?? decoded['total'] as int? ?? 0;
      final returnedOffset = decoded['offset'] as int? ?? offset;
      final returnedLimit = decoded['limit'] as int? ?? limit;
      final pageCount = decoded['pageCount'] as int?;

      final parsedTransactions = txList.map((t) {
        final tx = t as Map<String, dynamic>;
        final txType = (tx['type'] as String?) ?? 'received';
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final timestamp = tx['timestamp'] as int?;

        return {
          'txid': tx['txid'] as String,
          'amount': amount.abs(),
          'direction': txType == 'sent' ? 'sent' : txType == 'received' ? 'received' : 'received',
          'confirmations': 0,
          'timestamp': timestamp,
          'counterparty': null,
        };
      }).toList();

      return {
        'transactions': parsedTransactions,
        'txCount': txCount,
        'offset': returnedOffset,
        'limit': returnedLimit,
        'pageCount': pageCount,
      };
    } catch (_) {
      return {'transactions': [], 'txCount': 0};
    }
  }

  // Get network info
  Future<Map<String, dynamic>?> getNetworkInfo(
    String rpcUrl,
    String rpcUser,
    String rpcPassword,
  ) async {
    final blockchainInfo = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getblockchaininfo');
    final networkInfo = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getnetworkinfo');
    final mempoolInfo = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getmempoolinfo');
    final miningInfo = await rpcRequest(rpcUrl, rpcUser, rpcPassword, 'getmininginfo');

    if (blockchainInfo == null) return null;

    return {
      'blocks': blockchainInfo['result']?['blocks'],
      'difficulty': blockchainInfo['result']?['difficulty'],
      'bestblockhash': blockchainInfo['result']?['bestblockhash'],
      'mediantime': blockchainInfo['result']?['mediantime'],
      'version': networkInfo?['result']?['version'],
      'subversion': networkInfo?['result']?['subversion'],
      'connections': networkInfo?['result']?['connections'],
      'mempool_size': mempoolInfo?['result']?['size'],
      'mempool_bytes': mempoolInfo?['result']?['bytes'],
      'networkhashps': miningInfo?['result']?['networkhashps'],
    };
  }

  // Calculate balance from UTXOs
  double calculateBalance(List<Map<String, dynamic>> utxos) {
    return utxos
        .where((u) =>
            u['txid'] != 'pending_marker' &&
            (u['confirmations'] as int) > 0)  // ← only confirmed
        .fold(0.0, (sum, u) => sum + (u['amount'] as double));
  }

  double calculateUnconfirmedBalance(List<Map<String, dynamic>> utxos) {
    return utxos
        .where((u) =>
            u['txid'] != 'pending_marker' &&
            (u['confirmations'] as int) == 0)  // ← only unconfirmed
        .fold(0.0, (sum, u) => sum + (u['amount'] as double));
  }
}
