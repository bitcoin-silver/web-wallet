import 'package:flutter/material.dart';
import '../models/wallet_model.dart';
import '../services/wallet_service.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../config.dart';

class WalletProvider with ChangeNotifier {
  final WalletService _walletService = WalletService();
  final StorageService _storage = StorageService();
  static const bool _enableFeeDebugLogs = true;
  static const Duration _rememberSessionTtl = Duration(days: 7);
  static const int _maxMigrationSweepInputs = 120;
  static const int _maxMigrationSweepVbytes = 90000;
  static const int _maxCoinControlUtxos = 1500;

  WalletModel? _wallet;
  bool _isLoading = false;
  String _message = '';
  final Set<String> _localPendingTxs = {};
  List<TransactionModel> _transactions = [];
  bool _isLoadingTxs = false;
  int _txCount = 0;
  bool _rememberSessionEnabled = false;

  // RPC Config
  String _rpcUrl = 'https://bitcoinsilver.eu/btcs-rpc';
  String _rpcUser = '';
  String _rpcPassword = '';

  WalletModel? get wallet => _wallet;
  bool get isLoading => _isLoading;
  String get message => _message;
  bool get isLoaded => _wallet != null;
  bool get rememberSessionEnabled => _rememberSessionEnabled;
  bool get hasSessionEncryptionSecret =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(Config.sessionEncryptionSecretHex);

  // Expose walletService to let the setup UI generate local keys safely
  WalletService get walletService => _walletService;
  List<TransactionModel> get transactions => _transactions;
  List<TransactionModel> get visibleTransactions => _transactions;
  bool get hasMoreTransactions => _transactions.length < _txCount;
  bool get isLoadingTxs => _isLoadingTxs;
  double _feeRate = 0.00001;
  bool _isFetchingFeeRate = false;
  bool _feeRateReady = false;
  bool _usingManualFeeRate = false;
  String _feeRateSource = 'unavailable';
  double? _feeBaselineRate;
  double? _feeEstimatedRate;
  double? _feeSanityCeiling;
  String _feeRateStatusMessage = 'Fee estimate not requested yet.';
  // Coin control state
  List<Map<String, dynamic>> _availableUtxos = [];
  Set<String> _selectedUtxoKeys = {}; // "txid:vout"
  bool _isLoadingUtxos = false;
  int _utxoPage = 0;
  int _coinControlTruncatedCount = 0;
  static const int _utxosPerPage = 15;

  List<Map<String, dynamic>> get availableUtxos => _availableUtxos;
  Set<String> get selectedUtxoKeys => _selectedUtxoKeys;
  bool get isLoadingUtxos => _isLoadingUtxos;
  bool get isFetchingFeeRate => _isFetchingFeeRate;
  double get feeRate => _feeRate;
  bool get feeRateReady => _feeRateReady;
  bool get usingManualFeeRate => _usingManualFeeRate;
  String get feeRateSource => _feeRateSource;
  double? get feeBaselineRate => _feeBaselineRate;
  double? get feeEstimatedRate => _feeEstimatedRate;
  double? get feeSanityCeiling => _feeSanityCeiling;
  String get feeRateStatusMessage => _feeRateStatusMessage;
  int get utxoPage => _utxoPage;
  int get coinControlTruncatedCount => _coinControlTruncatedCount;
  int get utxoPageCount => (_availableUtxos.isEmpty) ? 1 : (_availableUtxos.length / _utxosPerPage).ceil();
  int get selectedUtxoCount => _selectedUtxoKeys.length;
  // Typical 1-in 2-out tx = 10 + 148 + 68 = 226 bytes
  double get estimatedSimpleFee => double.parse((_feeRate * 226 / 1000).toStringAsFixed(8));

  double get selectedUtxoTotal => _availableUtxos
      .where((u) => _selectedUtxoKeys.contains('${u['txid']}:${u['vout']}'))
      .fold(0.0, (sum, u) => sum + (u['amount'] as num).toDouble());

  List<Map<String, dynamic>> get selectedUtxoList => _availableUtxos
      .where((u) => _selectedUtxoKeys.contains('${u['txid']}:${u['vout']}'))
      .toList();

  List<Map<String, dynamic>> get currentPageUtxos {
    final start = _utxoPage * _utxosPerPage;
    final end = (start + _utxosPerPage).clamp(0, _availableUtxos.length);
    return _availableUtxos.sublist(start, end);
  }

  double get estimatedFee {
    if (_selectedUtxoKeys.isEmpty) return 0.0;
    final inputCount = _selectedUtxoKeys.length;
    final txSize = 10 + (inputCount * 148) + 2 * 34;
    return double.parse((_feeRate * txSize / 1000).toStringAsFixed(8));
  }

  double get estimatedNetSend {
    final net = selectedUtxoTotal - estimatedFee;
    return net > 0 ? net : 0.0;
  }

  Future<void> fetchFeeRate() async {
    _isFetchingFeeRate = true;
    _feeRateReady = false;
    _usingManualFeeRate = false;
    _feeRateSource = 'fetching';
    _feeBaselineRate = null;
    _feeEstimatedRate = null;
    _feeSanityCeiling = null;
    _feeRateStatusMessage = 'Fetching fee estimate from node...';
    notifyListeners();

    try {
      final feeResult = await _walletService.resolveFeeRate(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
      );
      if (feeResult['success'] == true) {
        _feeRate = (feeResult['feeRate'] as num).toDouble();
        _feeRateReady = true;
        _feeRateSource = (feeResult['source'] as String?) ?? 'estimated';
        _feeBaselineRate = (feeResult['baselineFeeRate'] as num?)?.toDouble();
        _feeEstimatedRate = (feeResult['estimatedFeeRate'] as num?)?.toDouble();
        _feeSanityCeiling = (feeResult['sanityCeiling'] as num?)?.toDouble();
        switch (_feeRateSource) {
          case 'clamped':
            if (_enableFeeDebugLogs) {
              debugPrint(
                '[fee] clamped estimator -> baseline '
                'est=${_feeEstimatedRate?.toStringAsFixed(8)} '
                'base=${_feeBaselineRate?.toStringAsFixed(8)} '
                'ceil=${_feeSanityCeiling?.toStringAsFixed(8)}',
              );
            }
            _feeRateStatusMessage =
                (feeResult['message'] as String?) ??
                'Smart fee outlier detected. Using node baseline fee.';
            break;
          case 'baseline':
            _feeRateStatusMessage =
                (feeResult['message'] as String?) ??
                'Using node baseline fee.';
            break;
          case 'manual':
            _feeRateStatusMessage =
                'Using manual fee rate (${_feeRate.toStringAsFixed(8)} BTCS/kvB).';
            break;
          case 'estimated':
          default:
            _feeRateStatusMessage = 'Fee estimate ready from node.';
            break;
        }
      } else {
        _feeRate = 0.0;
        _feeRateReady = false;
        _feeRateSource = 'unavailable';
        _feeBaselineRate = null;
        _feeEstimatedRate = null;
        _feeSanityCeiling = null;
        _feeRateStatusMessage =
            (feeResult['message'] as String?) ?? 'Fee estimation unavailable. Manual fee required.';
      }
    } catch (_) {
      _feeRate = 0.0;
      _feeRateReady = false;
      _feeRateSource = 'unavailable';
      _feeBaselineRate = null;
      _feeEstimatedRate = null;
      _feeSanityCeiling = null;
      _feeRateStatusMessage = 'Fee estimation unavailable. Enter a manual fee when sending.';
    } finally {
      _isFetchingFeeRate = false;
      notifyListeners();
    }
  }

  void setManualFeeRate(double feeRateCoinPerKb) {
    _feeRate = feeRateCoinPerKb;
    _feeRateReady = true;
    _usingManualFeeRate = true;
    _feeRateSource = 'manual';
    _feeBaselineRate = null;
    _feeEstimatedRate = null;
    _feeSanityCeiling = null;
    _feeRateStatusMessage =
        'Using manual fee rate (${feeRateCoinPerKb.toStringAsFixed(8)} BTCS/kvB).';
    notifyListeners();
  }

  Future<void> loadMoreTransactions() async {
    if (_wallet == null || _isLoadingTxs || !hasMoreTransactions) return;

    _isLoadingTxs = true;
    notifyListeners();

    try {
      final data = await _walletService.getTransactions(
        _wallet!.address,
        offset: _transactions.length,
        limit: 10,
        rpcUrl: _rpcUrl,
        rpcUser: _rpcUser,
        rpcPassword: _rpcPassword,
      );

      final rawList = data['transactions'] as List<Map<String, dynamic>>? ?? [];

      final newTxs = rawList.map((m) {
        final dir = m['direction'] as String;
        return TransactionModel(
          txid: m['txid'] as String,
          amount: (m['amount'] as num).toDouble(),
          direction: dir == 'sent'
              ? TxDirection.sent
              : dir == 'self'
                  ? TxDirection.selfTransfer
                  : TxDirection.received,
          confirmations: m['confirmations'] as int,
          timestamp: m['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (m['timestamp'] as int) * 1000)
              : null,
          counterpartyAddress: m['counterparty'] as String?,
        );
      }).toList();

      _transactions.addAll(newTxs);
    } catch (_) {
    } finally {
      _isLoadingTxs = false;
      notifyListeners();
    }
  }
 
  WalletProvider() {
    _loadRpcConfig();
    _initializeSessionPersistence();
  }

  Future<void> _initializeSessionPersistence() async {
    _rememberSessionEnabled = _storage.loadPersistentSessionEnabled();
    if (_rememberSessionEnabled) {
      await _restorePersistentSessionIfPossible();
    }
    notifyListeners();
  }

  Future<void> _restorePersistentSessionIfPossible() async {
    if (!hasSessionEncryptionSecret) {
      _rememberSessionEnabled = false;
      _storage.savePersistentSessionEnabled(false);
      _storage.clearPersistentSession();
      return;
    }

    final stored =
        _storage.loadPersistentSession(Config.sessionEncryptionSecretHex);
    if (stored == null) return;

    final type = stored['type'] as String?;
    final value = stored['value'] as String?;
    final savedAtRaw = stored['savedAt'] as String?;
    if (type == null || value == null || value.isEmpty) {
      _storage.clearPersistentSession();
      return;
    }

    if (savedAtRaw == null) {
      _storage.clearPersistentSession();
      return;
    }

    final savedAt = DateTime.tryParse(savedAtRaw);
    if (savedAt == null || DateTime.now().difference(savedAt) > _rememberSessionTtl) {
      _storage.clearPersistentSession();
      return;
    }

    final restored = await _restoreWalletFromPersistentSession(type, value);

    if (restored) {
      _message = '✅ Wallet restored.';
      notifyListeners();

      Future.delayed(const Duration(seconds: 5), () {
        if (_message == '✅ Wallet restored.') {
          _message = '';
          notifyListeners();
        }
      });
    }

    if (!restored) {
      _storage.clearPersistentSession();
    }
  }

  Future<bool> _restoreWalletFromPersistentSession(String type, String value) async {
    try {
      if (type == 'seed') {
        final walletData = await _walletService.getWalletFromMnemonic(value);
        if (walletData == null) return false;

        _wallet = WalletModel(
          address: walletData['address']!,
          privateKey: walletData['privateKey']!,
          mnemonic: value,
          type: WalletType.seed,
          balance: 0.0,
          unconfirmedBalance: 0.0,
          isPending: false,
        );
      } else if (type == 'wif') {
        final address = _walletService.getAddressFromWif(value);
        if (address == null) return false;

        _wallet = WalletModel(
          address: address,
          privateKey: value,
          type: WalletType.wif,
          balance: 0.0,
          unconfirmedBalance: 0.0,
          isPending: false,
        );
      } else {
        return false;
      }

      _isLoading = false;
      _message = '';

      // Best-effort network sync after local restore so cold starts still work offline.
      refreshBalance();
      fetchTransactions();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setRememberSessionEnabled(bool enabled) async {
    if (enabled && !hasSessionEncryptionSecret) {
      _rememberSessionEnabled = false;
      _storage.savePersistentSessionEnabled(false);
      _message =
          '❌ Remembered session requires SESSION_ENCRYPTION_SECRET_HEX (64 hex chars).';
      notifyListeners();
      return;
    }

    _rememberSessionEnabled = enabled;
    _storage.savePersistentSessionEnabled(enabled);

    if (!enabled) {
      _storage.clearPersistentSession();
      notifyListeners();
      return;
    }

    _persistCurrentSession();
    notifyListeners();
  }

  void _persistCurrentSession() {
    if (!_rememberSessionEnabled || _wallet == null || !hasSessionEncryptionSecret) return;

    final payload = {
      'type': _wallet!.type == WalletType.seed && (_wallet!.mnemonic?.isNotEmpty ?? false)
          ? 'seed'
          : 'wif',
      'value': _wallet!.type == WalletType.seed && (_wallet!.mnemonic?.isNotEmpty ?? false)
          ? _wallet!.mnemonic
          : _wallet!.privateKey,
      'savedAt': DateTime.now().toIso8601String(),
    };

    _storage.savePersistentSession(payload, Config.sessionEncryptionSecretHex);
  }

  void _loadRpcConfig() {
    final config = _storage.loadRpcConfig();
    if (config != null) {
      _rpcUrl = config['url']!;
      _rpcUser = config['user']!;
      _rpcPassword = config['password']!;
    }
  }

  void clearMessage() {
    _message = '';
    notifyListeners();
  }

  /// Private helper to verify RPC availability before making blocking network calls
  Future<bool> _isRpcAvailable() async {
    try {
      final info = await getNetworkInfo();
      
      // Ensure we got a valid map response, and verify a key that ONLY exists on successful nodes
      // Example: 'version', 'blocks', or 'protocolversion'
      if (info != null && (info.containsKey('version') || info.containsKey('blocks'))) {
        return true;
      }
      
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Private helper to fetch UTXOs and calculate balances, reducing code duplication
  Future<Map<String, dynamic>> _fetchAndPopulateWalletBalances(String address) async {
    final utxos = await _walletService.getUtxos(_rpcUrl, _rpcUser, _rpcPassword, address);
    final balance = _walletService.calculateBalance(utxos);
    final unconfirmed = _walletService.calculateUnconfirmedBalance(utxos);
    final hasMempoolActivity = utxos.any((u) => u['confirmations'] == 0);

    return {
      'balance': balance,
      'unconfirmedBalance': unconfirmed,
      'isPending': hasMempoolActivity,
    };
  }

  Future<void> refreshBalance() async {

      if (_wallet == null) return;

      try {
        // If rpcRequest throws an exception due to a 404/disconnect, it jumps straight to catch
        final utxos = await _walletService.getUtxos(
            _rpcUrl, _rpcUser, _rpcPassword, _wallet!.address);
            
        final balance = _walletService.calculateBalance(utxos);
        final unconfirmed = _walletService.calculateUnconfirmedBalance(utxos);
        final hasMempoolActivity = utxos.any((u) => u['confirmations'] == 0);

        if (!hasMempoolActivity) {
          _localPendingTxs.clear();
        }

        _wallet = _wallet!.copyWith(
          balance: balance,
          unconfirmedBalance: unconfirmed,
          isPending: hasMempoolActivity || _localPendingTxs.isNotEmpty,
        );
        
        // Clear any previous connection errors if it successfully fetches
        if (_message.contains('Connection lost')) _message = '';
        notifyListeners();
        // Refresh transaction history in background
        fetchTransactions();
      } catch (_) {
        // 💡 Update message state so the dashboard can show a 'Connection Lost / Working Offline' banner
        _message = '⚠️ Connection lost. Displaying cached balances.';
        notifyListeners();
      }
  }

  /// Fetch first page of transactions for the current wallet address.
  Future<void> fetchTransactions() async {
    if (_wallet == null) return;
    _isLoadingTxs = true;
    notifyListeners();

    try {
      final data = await _walletService.getTransactions(
        _wallet!.address,
        offset: 0,
        limit: 10,
        rpcUrl: _rpcUrl,
        rpcUser: _rpcUser,
        rpcPassword: _rpcPassword,
      );
      final rawList = data['transactions'] as List<Map<String, dynamic>>? ?? [];
      _txCount = data['txCount'] as int? ?? 0;

      _transactions = rawList.map((m) {
        final dir = m['direction'] as String;
        return TransactionModel(
          txid: m['txid'] as String,
          amount: (m['amount'] as num).toDouble(),
          direction: dir == 'sent'
              ? TxDirection.sent
              : dir == 'self'
                  ? TxDirection.selfTransfer
                  : TxDirection.received,
          confirmations: m['confirmations'] as int,
          timestamp: m['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (m['timestamp'] as int) * 1000)
              : null,
          counterpartyAddress: m['counterparty'] as String?,
        );
      }).toList();
    } catch (_) {
      // silently ignore — history is non-critical
    } finally {
      _isLoadingTxs = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> sendTransaction(
    String toAddress,
    double amount, {
    double? manualFeeRateCoinPerKb,
    bool preferBatchSend = true,
  }) async {
    if (_wallet == null) {
      return {
        'success': false,
        'message': 'Wallet not loaded.',
      };
    }

    _isLoading = true;
    _message = '⏳ Sending transaction...';
    notifyListeners();

    try {
      final hasExplicitSelection = _selectedUtxoKeys.isNotEmpty;
      final confirmedUtxos = hasExplicitSelection
          ? selectedUtxoList
              .where((u) =>
                  u['txid'] != 'pending_marker' &&
                  ((u['confirmations'] as int?) ?? 0) > 0)
              .toList()
          : (await _walletService.getUtxos(
              _rpcUrl,
              _rpcUser,
              _rpcPassword,
              _wallet!.address,
            ))
              .where((u) =>
                  u['txid'] != 'pending_marker' &&
                  ((u['confirmations'] as int?) ?? 0) > 0)
              .toList();

      final confirmedTotal = confirmedUtxos.fold<double>(
        0.0,
        (sum, u) => sum + (u['amount'] as num).toDouble(),
      );
      final nearSweep = amount >= (confirmedTotal - 0.00001);
      final estimatedSweepVbytes = 11 + (confirmedUtxos.length * 68) + 31;
      final tooLargeForSingleSweep =
          confirmedUtxos.length > _maxMigrationSweepInputs ||
              estimatedSweepVbytes > _maxMigrationSweepVbytes;

      if (preferBatchSend && nearSweep && tooLargeForSingleSweep && confirmedUtxos.isNotEmpty) {
        final batchResult = await _sendSweepInBatches(
          toAddress,
          confirmedUtxos,
          manualFeeRateCoinPerKb: manualFeeRateCoinPerKb,
        );

        _isLoading = false;
        if (batchResult['success'] == true) {
          final txids = (batchResult['batchTxids'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          _message =
              '✅ Batch send complete: ${txids.length} transaction${txids.length == 1 ? '' : 's'} broadcasted.';
          await refreshBalance();
          notifyListeners();

          Future.delayed(const Duration(seconds: 5), () {
            if (_message.contains('✅')) _message = '';
            notifyListeners();
          });
          return batchResult;
        }

        _message = '❌ ${batchResult['message']}';
        notifyListeners();
        return batchResult;
      }
    } catch (_) {
      // Fall through to regular single-transaction path if preflight cannot complete.
    }

    Map<String, dynamic> result;
    try {
      result = await _walletService.sendTransaction(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
        _wallet!.privateKey,
        _wallet!.address,
        toAddress,
        amount,
        manualFeeRateCoinPerKb: manualFeeRateCoinPerKb,
        preSelectedUtxos: _selectedUtxoKeys.isNotEmpty ? selectedUtxoList : null,
      );
    } catch (e) {
      _isLoading = false;
      _message = '❌ Send failed: ${e.toString().replaceAll('Exception: ', '')}';
      notifyListeners();
      return {
        'success': false,
        'message': _message.replaceFirst('❌ ', ''),
      };
    }

    _isLoading = false;
    if (result['success']) {
      final txid = result['txid'] as String;
      _localPendingTxs.add(txid);
      
      _message = '✅ Sent! TXID: $txid';
      await refreshBalance();
      notifyListeners();
      
      // Auto-clear success message
      Future.delayed(const Duration(seconds: 5), () {
        if (_message.contains('✅')) _message = '';
        notifyListeners();
      });
      return result;
    } else {
      _message = '❌ ${result['message']}';
      notifyListeners();
      return result;
    }
  }

  Future<Map<String, dynamic>> assessBatchSendCandidate(
    String toAddress,
    double amount, {
    double? manualFeeRateCoinPerKb,
  }) async {
    if (_wallet == null || amount <= 0) {
      return {
        'isCandidate': false,
        'reason': 'invalid-state',
      };
    }

    final hasExplicitSelection = _selectedUtxoKeys.isNotEmpty;
    final confirmedUtxos = hasExplicitSelection
        ? selectedUtxoList
            .where((u) =>
                u['txid'] != 'pending_marker' &&
                ((u['confirmations'] as int?) ?? 0) > 0)
            .toList()
        : (await _walletService.getUtxos(
            _rpcUrl,
            _rpcUser,
            _rpcPassword,
            _wallet!.address,
          ))
            .where((u) =>
                u['txid'] != 'pending_marker' &&
                ((u['confirmations'] as int?) ?? 0) > 0)
            .toList();

    if (confirmedUtxos.isEmpty) {
      return {
        'isCandidate': false,
        'reason': 'no-utxos',
      };
    }

    final confirmedTotal = confirmedUtxos.fold<double>(
      0.0,
      (sum, u) => sum + (u['amount'] as num).toDouble(),
    );
    final nearSweep = amount >= (confirmedTotal - 0.00001);

    final sortedAmounts = confirmedUtxos
        .map((u) => (u['amount'] as num).toDouble())
        .toList()
      ..sort((a, b) => b.compareTo(a));

    int toSats(double v) => (v * 1e8).round();
    int estimateFeeSats(double feeRate, int vbytes) =>
        (feeRate * vbytes / 1000 * 1e8).round();

    final feeRate = manualFeeRateCoinPerKb ?? (this.feeRate > 0 ? this.feeRate : 0.00001);
    final isDestLegacy = !toAddress.toLowerCase().startsWith('s2');
    final destOutputSize = isDestLegacy ? 34 : 31;
    final changeOutputSize = 31;

    int predictedInputCount;
    int predictedVbytes;

    if (nearSweep) {
      predictedInputCount = sortedAmounts.length;
      predictedVbytes = 11 + (predictedInputCount * 68) + destOutputSize;
    } else {
      final targetSats = toSats(amount);
      var used = 0;
      var inputSumSats = 0;
      while (used < sortedAmounts.length) {
        inputSumSats += toSats(sortedAmounts[used]);
        used += 1;
        final txSize = 11 + (used * 68) + destOutputSize + changeOutputSize;
        final feeSats = estimateFeeSats(feeRate, txSize);
        if (inputSumSats >= targetSats + feeSats) {
          break;
        }
      }
      predictedInputCount = used;
      predictedVbytes = 11 + (predictedInputCount * 68) + destOutputSize + changeOutputSize;
    }

    final exceedsInputs = predictedInputCount > _maxMigrationSweepInputs;
    final exceedsVbytes = predictedVbytes > _maxMigrationSweepVbytes;
    final sweepTrigger = nearSweep &&
        (sortedAmounts.length > _maxMigrationSweepInputs ||
            (11 + (sortedAmounts.length * 68) + 31) > _maxMigrationSweepVbytes);
    // Batch send implementation is sweep-oriented in this flow, so only
    // suggest batch when the request is effectively a near-sweep transfer.
    final isCandidate = nearSweep && (sweepTrigger || exceedsInputs || exceedsVbytes);

    final chunkSize = _maxSweepInputsPerBatchTx();
    final estimatedBatchCount =
        predictedInputCount <= 0 ? 1 : ((predictedInputCount + chunkSize - 1) ~/ chunkSize);
    final singleFee = feeRate * predictedVbytes / 1000;
    final estimatedTotalBatchFee = singleFee * estimatedBatchCount;

    final reason = sweepTrigger
        ? 'sweep-too-large'
        : exceedsInputs
            ? 'input-count'
            : exceedsVbytes
                ? 'tx-size'
                : 'none';

    return {
      'isCandidate': isCandidate,
      'reason': reason,
      'nearSweep': nearSweep,
      'predictedInputCount': predictedInputCount,
      'predictedVbytes': predictedVbytes,
      'estimatedBatchCount': estimatedBatchCount,
      'estimatedSingleFee': double.parse(singleFee.toStringAsFixed(8)),
      'estimatedTotalBatchFee': double.parse(estimatedTotalBatchFee.toStringAsFixed(8)),
      'estimatedNetDelivered':
          double.parse((amount - estimatedTotalBatchFee).toStringAsFixed(8)),
      'confirmedUtxoCount': confirmedUtxos.length,
      'confirmedTotal': double.parse(confirmedTotal.toStringAsFixed(8)),
    };
  }

  int _maxSweepInputsPerBatchTx() {
    final maxByVbytes = ((_maxMigrationSweepVbytes - 42) ~/ 68);
    if (maxByVbytes <= 0) return 1;
    return maxByVbytes < _maxMigrationSweepInputs
        ? maxByVbytes
        : _maxMigrationSweepInputs;
  }

  List<List<Map<String, dynamic>>> _chunkUtxosForSweep(
    List<Map<String, dynamic>> confirmedUtxos,
  ) {
    final chunkSize = _maxSweepInputsPerBatchTx();
    final sorted = List<Map<String, dynamic>>.from(confirmedUtxos)
      ..sort((a, b) =>
          ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));

    final chunks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < sorted.length; i += chunkSize) {
      final end = (i + chunkSize < sorted.length) ? i + chunkSize : sorted.length;
      chunks.add(sorted.sublist(i, end));
    }
    return chunks;
  }

  Future<Map<String, dynamic>> _sendSweepInBatches(
    String toAddress,
    List<Map<String, dynamic>> confirmedUtxos, {
    double? manualFeeRateCoinPerKb,
  }) async {
    if (_wallet == null) {
      return {
        'success': false,
        'message': 'Wallet not loaded.',
      };
    }

    final chunks = _chunkUtxosForSweep(confirmedUtxos);
    if (chunks.isEmpty) {
      return {
        'success': false,
        'message': 'No confirmed UTXOs available for batch send.',
      };
    }

    final txids = <String>[];
    double totalFee = 0.0;
    double grossSent = 0.0;

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkAmount = chunk.fold<double>(
        0.0,
        (sum, u) => sum + (u['amount'] as num).toDouble(),
      );

      _message = '⏳ Broadcasting batch ${i + 1}/${chunks.length}...';
      notifyListeners();

      final result = await _walletService.sendTransaction(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
        _wallet!.privateKey,
        _wallet!.address,
        toAddress,
        chunkAmount,
        manualFeeRateCoinPerKb: manualFeeRateCoinPerKb,
        preSelectedUtxos: chunk,
      );

      if (result['success'] != true) {
        final baseMessage = (result['message'] as String?) ??
            'Unknown error while broadcasting batch ${i + 1}.';
        return {
          'success': false,
          'batched': true,
          'batchTxids': txids,
          'completedBatches': txids.length,
          'totalBatches': chunks.length,
          'requiresManualFee': result['requiresManualFee'] == true,
          'feeEstimationFailed': result['feeEstimationFailed'] == true,
          'message': 'Batch ${i + 1}/${chunks.length} failed after '
              '${txids.length} successful batch(es). $baseMessage',
        };
      }

      final txid = (result['txid'] as String?) ?? '';
      if (txid.isNotEmpty) {
        txids.add(txid);
        _localPendingTxs.add(txid);
      }

      final fee = (result['fee'] as num?)?.toDouble() ?? 0.0;
      totalFee += fee;
      grossSent += chunkAmount;
    }

    return {
      'success': true,
      'batched': true,
      'batchTxids': txids,
      'batchCount': chunks.length,
      'grossAmount': grossSent,
      'fee': totalFee,
      'netAmount': grossSent - totalFee,
    };
  }

  Future<void> fetchUtxosForCoinControl() async {
    if (_wallet == null) return;
    _isLoadingUtxos = true;
    _availableUtxos = [];
    _selectedUtxoKeys = {};
    _utxoPage = 0;
    _coinControlTruncatedCount = 0;
    notifyListeners();

    try {
      final all = await _walletService.getUtxos(
        _rpcUrl, _rpcUser, _rpcPassword, _wallet!.address,
      );
      _availableUtxos = all
          .where((u) => u['txid'] != 'pending_marker' && (u['confirmations'] as int) > 0)
          .toList();
      _availableUtxos.sort((a, b) =>
          (b['amount'] as num).toDouble().compareTo((a['amount'] as num).toDouble()));

      if (_availableUtxos.length > _maxCoinControlUtxos) {
        _coinControlTruncatedCount = _availableUtxos.length - _maxCoinControlUtxos;
        _availableUtxos = _availableUtxos.sublist(0, _maxCoinControlUtxos);
      }

      await fetchFeeRate();
    } catch (_) {
    } finally {
      _isLoadingUtxos = false;
      notifyListeners();
    }
  }

  void toggleUtxo(String key) {
    if (_selectedUtxoKeys.contains(key)) {
      _selectedUtxoKeys.remove(key);
    } else {
      _selectedUtxoKeys.add(key);
    }
    notifyListeners();
  }

  void selectAllUtxos() {
    _selectedUtxoKeys = _availableUtxos
        .map((u) => '${u['txid']}:${u['vout']}')
        .toSet();
    notifyListeners();
  }

  void clearUtxoSelection() {
    _selectedUtxoKeys = {};
    notifyListeners();
  }

  void setUtxoPage(int page) {
    _utxoPage = page;
    notifyListeners();
  }

  // Call this when send view closes, to reset state
  void resetCoinControl() {
    _availableUtxos = [];
    _selectedUtxoKeys = {};
    _utxoPage = 0;
    _isLoadingUtxos = false;
    _coinControlTruncatedCount = 0;
  }

  Future<bool> validateAddress(String address) async {
    if (address.isEmpty) return false;
    try {
      final result = await _walletService.rpcRequest(
        _rpcUrl, _rpcUser, _rpcPassword, 'validateaddress', [address]);
      return result != null &&
          result['result'] != null &&
          result['result']['isvalid'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getNetworkInfo() async {
    return await _walletService.getNetworkInfo(_rpcUrl, _rpcUser, _rpcPassword);
  }

  Future<List<Map<String, dynamic>>> _getConfirmedMigrationUtxos(
    String sourceAddress,
  ) async {
    final allUtxos = await _walletService.getUtxos(
      _rpcUrl,
      _rpcUser,
      _rpcPassword,
      sourceAddress,
    );

    return allUtxos
        .where((u) =>
            u['txid'] != 'pending_marker' &&
            ((u['confirmations'] as int?) ?? 0) > 0)
        .toList();
  }

  Future<String?> _validateMigrationSweepGate(
    List<Map<String, dynamic>> confirmedUtxos,
    double confirmedBalance,
  ) async {
    try {
      if (confirmedUtxos.isEmpty) {
        return 'Migration blocked: no confirmed inputs are available.';
      }

      final inputCount = confirmedUtxos.length;
      final estimatedVbytes = inputCount > _maxMigrationSweepInputs
          ? 11 + (_maxMigrationSweepInputs * 68) + 31
          : 11 + (inputCount * 68) + 31;

      final feeResolution = await _walletService.resolveFeeRate(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
      );

      if (feeResolution['success'] != true) {
        final detail =
            (feeResolution['message'] as String?) ?? 'Smart fee unavailable.';
        return 'Migration blocked: $detail';
      }

      final feeRate = (feeResolution['feeRate'] as num).toDouble();
      final estimatedFee = double.parse(
        (feeRate * estimatedVbytes / 1000).toStringAsFixed(8),
      );

      if (confirmedBalance <= estimatedFee + 0.00000546) {
        return 'Migration blocked: confirmed balance '
            '(${confirmedBalance.toStringAsFixed(8)} BTCS) is too low after '
            'estimated fee (${estimatedFee.toStringAsFixed(8)} BTCS).';
      }

      return null;
    } catch (_) {
      return 'Migration blocked: preflight safety checks failed due to a network or node error.';
    }
  }

  Future<Map<String, dynamic>> assessMigrationBatchCandidate() async {
    if (_wallet == null || _wallet!.type != WalletType.wif) {
      return {
        'isCandidate': false,
        'reason': 'invalid-wallet',
      };
    }

    final confirmedUtxos = await _getConfirmedMigrationUtxos(_wallet!.address);
    final inputCount = confirmedUtxos.length;
    final estimatedVbytes = 11 + (inputCount * 68) + 31;
    final isCandidate = inputCount > _maxMigrationSweepInputs ||
        estimatedVbytes > _maxMigrationSweepVbytes;

    final chunkSize = _maxSweepInputsPerBatchTx();
    final estimatedBatchCount =
        inputCount <= 0 ? 1 : ((inputCount + chunkSize - 1) ~/ chunkSize);

    final confirmedTotal = confirmedUtxos.fold<double>(
      0.0,
      (sum, u) => sum + (u['amount'] as num).toDouble(),
    );

    String reason;
    if (inputCount > _maxMigrationSweepInputs) {
      reason = 'input-count';
    } else if (estimatedVbytes > _maxMigrationSweepVbytes) {
      reason = 'tx-size';
    } else {
      reason = 'none';
    }

    return {
      'isCandidate': isCandidate,
      'reason': reason,
      'inputCount': inputCount,
      'estimatedVbytes': estimatedVbytes,
      'estimatedBatchCount': estimatedBatchCount,
      'confirmedTotal': double.parse(confirmedTotal.toStringAsFixed(8)),
    };
  }

  void logout() {
    _wallet = null;
    _isLoading = false;
    _message = '';
    _transactions = [];
    _isLoadingTxs = false;
    _localPendingTxs.clear();
    _storage.clearSession();
    _storage.clearDisclaimerAccepted();
    if (!_rememberSessionEnabled) {
      _storage.clearPersistentSession();
    }
    notifyListeners();
  }

  // Changed from Future<void> to Future<bool>
  Future<bool> loadSeedWallet(
    String mnemonic, {
    bool persistSession = true,
    bool showLoadedMessage = true,
  }) async {
    _isLoading = true;
    _message = '⏳ Loading wallet...';
    notifyListeners();

    // Give the UI a moment to render the spinner
    await Future.delayed(const Duration(milliseconds: 500));

    // 1. Validate the RPC Connection first
    if (!await _isRpcAvailable()) {
      _message = '❌ RPC Connection unavailable. Check your network.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final walletData = await _walletService.getWalletFromMnemonic(mnemonic);
    if (walletData == null) {
      _message = '❌ Invalid Seed Phrase';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final address = walletData['address']!;
    final wif = walletData['privateKey']!;

    try {
      // 2. Fetch network balances using the shared helper
      final walletBalances = await _fetchAndPopulateWalletBalances(address);

      _wallet = WalletModel(
        address: address,
        privateKey: wif,
        mnemonic: mnemonic,
        type: WalletType.seed,
        balance: walletBalances['balance'],
        unconfirmedBalance: walletBalances['unconfirmedBalance'],
        isPending: walletBalances['isPending'],
      );

      _isLoading = false;
      _message = showLoadedMessage ? '✅ Wallet loaded successfully!' : '';
      if (persistSession) {
        _persistCurrentSession();
      }
      notifyListeners();
      
      // Auto-clear success message
      if (showLoadedMessage) {
        Future.delayed(const Duration(seconds: 5), () {
          if (_message.contains('✅')) _message = '';
          notifyListeners();
        });
      }
      // Load transaction history in background
      fetchTransactions();

      return true;
    } catch (e) {
      _message = '❌ Failed to fetch wallet data: ${e.toString().replaceAll('Exception: ', '')}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Changed from Future<void> to Future<bool>
  Future<bool> loadWifWallet(
    String wif, {
    bool persistSession = true,
    bool showLoadedMessage = true,
  }) async {
    _isLoading = true;
    _message = '⏳ Loading wallet...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    // 1. Validate the RPC Connection first
    if (!await _isRpcAvailable()) {
      _message = '❌ RPC Connection unavailable. Check your network.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    try {
      final address = _walletService.getAddressFromWif(wif);
      if (address == null) {
        _message = '❌ Invalid WIF Private Key';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Fetch network balances using the shared helper
      final walletBalances = await _fetchAndPopulateWalletBalances(address);

      _wallet = WalletModel(
        address: address,
        privateKey: wif,
        type: WalletType.wif,
        balance: walletBalances['balance'],
        unconfirmedBalance: walletBalances['unconfirmedBalance'],
        isPending: walletBalances['isPending'],
      );

      _isLoading = false;
      _message = showLoadedMessage ? '✅ Wallet loaded successfully!' : '';
      if (persistSession) {
        _persistCurrentSession();
      }
      notifyListeners();
      
      // Auto-clear success message
      if (showLoadedMessage) {
        Future.delayed(const Duration(seconds: 5), () {
          if (_message.contains('✅')) _message = '';
          notifyListeners();
        });
      }
      
      // Load transaction history in background
      fetchTransactions();

      return true;
    } catch (e) {
      _message = '❌ ${e.toString().replaceAll('Exception: ', '')}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> migrateToSeed({
    int words = 12,
    bool skipSweep = false,
    bool preferBatchSweep = false,
  }) async {
    if (_wallet == null || _wallet!.type != WalletType.wif) return false;

    _isLoading = true;
    _message = '⏳ Generating new seed phrase...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    final oldWif = _wallet!.privateKey;
    final oldAddress = _wallet!.address;

    await refreshBalance();
    final latestWallet = _wallet;
    if (latestWallet == null) {
      _isLoading = false;
      _message = '❌ Migration failed: wallet state unavailable.';
      notifyListeners();
      return false;
    }

    if (latestWallet.hasPending) {
      _isLoading = false;
      _message = '❌ Migration blocked: pending transactions detected. Wait for confirmations and retry.';
      notifyListeners();
      return false;
    }

    final currentBalance = latestWallet.balance;
    List<Map<String, dynamic>> migrationUtxos = const [];

    if (currentBalance > 0.00001 && !skipSweep) {
      migrationUtxos = await _getConfirmedMigrationUtxos(oldAddress);
      final migrationGateReason = await _validateMigrationSweepGate(
        migrationUtxos,
        currentBalance,
      );
      if (migrationGateReason != null) {
        _isLoading = false;
        _message = '❌ $migrationGateReason';
        notifyListeners();
        return false;
      }
    }
    
    final walletData = await _walletService.generateNewSeedWallet(words: words);
    final mnemonic = walletData['mnemonic']!;
    final newAddress = walletData['address']!;
    final newWif = walletData['privateKey']!;

    if (currentBalance > 0.00001 && !skipSweep) {
      final estimatedSweepVbytes = 11 + (migrationUtxos.length * 68) + 31;
      final useChunkedSweep = migrationUtxos.length > _maxMigrationSweepInputs ||
          estimatedSweepVbytes > _maxMigrationSweepVbytes;

      if (useChunkedSweep) {
        if (!preferBatchSweep) {
          _isLoading = false;
          _message =
              '❌ Migration blocked: this wallet requires multiple sweep transactions. '
              'Enable batch migration and retry.';
          notifyListeners();
          return false;
        }

        final batchResult = await _sendMigrationSweepInBatches(
          destinationAddress: newAddress,
          sourceWif: oldWif,
          sourceAddress: oldAddress,
          confirmedUtxos: migrationUtxos,
        );

        final batchTxids = (batchResult['batchTxids'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .where((txid) => txid.isNotEmpty)
            .toList();
        for (final txid in batchTxids) {
          _localPendingTxs.add(txid);
        }

        if (batchResult['success'] == true) {
          _wallet = WalletModel(
            address: newAddress,
            privateKey: newWif,
            mnemonic: mnemonic,
            type: WalletType.seed,
            balance: 0.0,
          );

          _isLoading = false;
          _message =
              '✅ Batch migration successful! ${batchTxids.length} transaction${batchTxids.length == 1 ? '' : 's'} broadcasted.';
          notifyListeners();
          _persistCurrentSession();

          Future.delayed(const Duration(seconds: 5), () {
            if (_message.contains('✅')) _message = '';
            notifyListeners();
          });

          refreshBalance();
          return true;
        }

        if (batchTxids.isNotEmpty) {
          _wallet = WalletModel(
            address: newAddress,
            privateKey: newWif,
            mnemonic: mnemonic,
            type: WalletType.seed,
            balance: 0.0,
          );

          _isLoading = false;
          _message =
              '⚠️ Migration partially completed (${batchTxids.length}/${(batchResult['totalBatches'] as int?) ?? 0} batches). '
              'Some funds were already moved to the new wallet. Back up the new seed now.';
          notifyListeners();
          _persistCurrentSession();
          refreshBalance();
          return true;
        }

        _isLoading = false;
        _message = '❌ Migration failed: ${batchResult['message']}';
        notifyListeners();
        return false;
      } else {
        _message = '⏳ Sweeping funds to new address...';
        notifyListeners();

        final migrationFeeResolution = await _walletService.resolveFeeRate(
          _rpcUrl,
          _rpcUser,
          _rpcPassword,
        );
        if (migrationFeeResolution['success'] != true) {
          _isLoading = false;
          _message = '❌ Migration failed: could not establish a safe fee rate.';
          notifyListeners();
          return false;
        }

        final migrationFeeSource =
            (migrationFeeResolution['source'] as String?) ?? 'unavailable';
        const allowedNodeSources = {'estimated', 'baseline', 'clamped'};
        if (!allowedNodeSources.contains(migrationFeeSource)) {
          _isLoading = false;
          _message =
              '❌ Migration failed: node fee estimate unavailable '
              '(source: $migrationFeeSource).';
          notifyListeners();
          return false;
        }

        final migrationFeeRate =
            (migrationFeeResolution['feeRate'] as num).toDouble();

        final result = await _walletService.sendTransaction(
          _rpcUrl,
          _rpcUser,
          _rpcPassword,
          oldWif,
          oldAddress,
          newAddress,
          currentBalance,
          manualFeeRateCoinPerKb: migrationFeeRate,
        );

        if (!result['success']) {
          _isLoading = false;
          _message = '❌ Migration failed: ${result['message']}';
          notifyListeners();
          return false; // Exits safely without losing access to the old WIF wallet!
        }
        _localPendingTxs.add(result['txid'] as String);
      }
    }

    _wallet = WalletModel(
      address: newAddress,
      privateKey: newWif,
      mnemonic: mnemonic,
      type: WalletType.seed,
      balance: 0.0,
    );
    
    _isLoading = false;
    _message = currentBalance > 0 
      ? '✅ Migration successful! Funds swept.' 
      : '✅ Migration successful! (Empty wallet)';
    notifyListeners();
    _persistCurrentSession();

    Future.delayed(const Duration(seconds: 5), () {
      if (_message.contains('✅')) _message = '';
      notifyListeners();
    });
    
    refreshBalance();
    return true;
  }

  Future<Map<String, dynamic>> _sendMigrationSweepInBatches({
    required String destinationAddress,
    required String sourceWif,
    required String sourceAddress,
    required List<Map<String, dynamic>> confirmedUtxos,
  }) async {
    final chunks = _chunkUtxosForSweep(confirmedUtxos);
    if (chunks.isEmpty) {
      return {
        'success': false,
        'message': 'No confirmed UTXOs available for migration batch sweep.',
      };
    }

    final feeResolution = await _walletService.resolveFeeRate(
      _rpcUrl,
      _rpcUser,
      _rpcPassword,
    );

    if (feeResolution['success'] != true) {
      return {
        'success': false,
        'message': 'Could not establish safe fee rate for batch migration.',
      };
    }

    final migrationFeeSource = (feeResolution['source'] as String?) ?? 'unavailable';
    const allowedNodeSources = {'estimated', 'baseline', 'clamped'};
    if (!allowedNodeSources.contains(migrationFeeSource)) {
      return {
        'success': false,
        'message': 'Node fee estimate unavailable for batch migration (source: $migrationFeeSource).',
      };
    }

    final migrationFeeRate = (feeResolution['feeRate'] as num).toDouble();

    final txids = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkAmount = chunk.fold<double>(
        0.0,
        (sum, u) => sum + (u['amount'] as num).toDouble(),
      );

      _message = '⏳ Migrating batch ${i + 1}/${chunks.length}...';
      notifyListeners();

      final result = await _walletService.sendTransaction(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
        sourceWif,
        sourceAddress,
        destinationAddress,
        chunkAmount,
        manualFeeRateCoinPerKb: migrationFeeRate,
        preSelectedUtxos: chunk,
      );

      if (result['success'] != true) {
        return {
          'success': false,
          'batchTxids': txids,
          'completedBatches': txids.length,
          'totalBatches': chunks.length,
          'message': result['message'] ??
              'Batch migration failed at ${i + 1}/${chunks.length}.',
        };
      }

      final txid = (result['txid'] as String?) ?? '';
      if (txid.isNotEmpty) {
        txids.add(txid);
      }
    }

    return {
      'success': true,
      'batchTxids': txids,
      'totalBatches': chunks.length,
    };
  }
}