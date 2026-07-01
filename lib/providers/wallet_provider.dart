import 'package:flutter/material.dart';
import '../models/wallet_model.dart';
import '../services/wallet_service.dart';
import '../models/transaction_model.dart';
import '../services/storage_service.dart';
import '../config.dart';

class WalletProvider with ChangeNotifier {
  final WalletService _walletService = WalletService();
  final StorageService _storage = StorageService();
  static const Duration _rememberSessionTtl = Duration(days: 7);

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
  String _feeRateStatusMessage = 'Fee estimate not requested yet.';
  // Coin control state
  List<Map<String, dynamic>> _availableUtxos = [];
  Set<String> _selectedUtxoKeys = {}; // "txid:vout"
  bool _isLoadingUtxos = false;
  int _utxoPage = 0;
  static const int _utxosPerPage = 15;

  List<Map<String, dynamic>> get availableUtxos => _availableUtxos;
  Set<String> get selectedUtxoKeys => _selectedUtxoKeys;
  bool get isLoadingUtxos => _isLoadingUtxos;
  bool get isFetchingFeeRate => _isFetchingFeeRate;
  bool get feeRateReady => _feeRateReady;
  bool get usingManualFeeRate => _usingManualFeeRate;
  String get feeRateStatusMessage => _feeRateStatusMessage;
  int get utxoPage => _utxoPage;
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
        _feeRateStatusMessage = 'Fee estimate ready from node.';
      } else {
        _feeRate = 0.0;
        _feeRateReady = false;
        _feeRateStatusMessage =
            (feeResult['message'] as String?) ?? 'Fee estimation unavailable. Manual fee required.';
      }
    } catch (_) {
      _feeRate = 0.0;
      _feeRateReady = false;
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
    _feeRateStatusMessage =
        'Using manual fee rate (${feeRateCoinPerKb.toStringAsFixed(8)} BTCS/kB).';
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

    final result = await _walletService.sendTransaction(
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

  Future<void> fetchUtxosForCoinControl() async {
    if (_wallet == null) return;
    _isLoadingUtxos = true;
    _availableUtxos = [];
    _selectedUtxoKeys = {};
    _utxoPage = 0;
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

  void logout() {
    _wallet = null;
    _isLoading = false;
    _message = '';
    _transactions = [];
    _isLoadingTxs = false;
    _localPendingTxs.clear();
    _storage.clearSession();
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

  Future<bool> migrateToSeed({int words = 12, bool skipSweep = false}) async {
    if (_wallet == null || _wallet!.type != WalletType.wif) return false;

    _isLoading = true;
    _message = '⏳ Generating new seed phrase...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    final oldWif = _wallet!.privateKey;
    final oldAddress = _wallet!.address;

    await refreshBalance();
    final currentBalance = _wallet!.balance;
    
    final walletData = await _walletService.generateNewSeedWallet(words: words);
    final mnemonic = walletData['mnemonic']!;
    final newAddress = walletData['address']!;
    final newWif = walletData['privateKey']!;

    if (currentBalance > 0.00001 && !skipSweep) {
      _message = '⏳ Sweeping funds to new address...';
      notifyListeners();

      final result = await _walletService.sendTransaction(
        _rpcUrl,
        _rpcUser,
        _rpcPassword,
        oldWif,
        oldAddress,
        newAddress,
        currentBalance,
      );

      if (!result['success']) {
        _isLoading = false;
        _message = '❌ Migration failed: ${result['message']}';
        notifyListeners();
        return false; // Exits safely without losing access to the old WIF wallet!
      }
      _localPendingTxs.add(result['txid'] as String);
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
}