import 'package:flutter/material.dart';
import 'wallet_service.dart';
import 'storage_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';

void main() {
  runApp(const BTCSWebWallet());
}

class BTCSWebWallet extends StatelessWidget {
  const BTCSWebWallet({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitcoin Silver Web Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFC0C0C0),
          secondary: const Color(0xFF00E5FF),
          surface: const Color(0xFF1A1A1A),
          background: const Color(0xFF0A0A0A),
        ),
      ),
      home: const WalletHome(),
    );
  }
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key});

  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  final WalletService _walletService = WalletService();
  final StorageService _storage = StorageService();

  final TextEditingController _privateKeyController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _toAddressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  String? _address;
  double _balance = 0.0;
  bool _isLoading = false;
  String _message = '';

  // Default RPC configuration (encoded)
  late String _rpcUrl;
  late String _rpcUser;
  late String _rpcPassword;

  String _decodeConfig(String encoded) {
    return String.fromCharCodes(base64Decode(encoded));
  }

  @override
  void initState() {
    super.initState();
    // Decode RPC configuration
    _rpcUrl = _decodeConfig('aHR0cDovLzIxMy4xNjUuODMuOTQ6MTA1Njc=');
    _rpcUser = _decodeConfig('b2xhZnNjaG9seg==');
    _rpcPassword = _decodeConfig('MUJJVENPSU5TSUxWRVIhMQ==');
    _loadRpcConfig();
  }

  void _loadRpcConfig() {
    final config = _storage.loadRpcConfig();
    if (config != null) {
      _rpcUrl = config['url']!;
      _rpcUser = config['user']!;
      _rpcPassword = config['password']!;
    }
  }

  Future<void> _loadWallet() async {
    final privateKey = _privateKeyController.text.trim();
    if (privateKey.isEmpty) {
      setState(() => _message = 'Please enter private key');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    final address = _walletService.getAddressFromWif(privateKey);
    if (address == null) {
      setState(() {
        _isLoading = false;
        _message = 'Invalid private key';
      });
      return;
    }

    // Get UTXOs and balance
    final utxos = await _walletService.getUtxos(_rpcUrl, _rpcUser, _rpcPassword, address);
    final balance = _walletService.calculateBalance(utxos);

    setState(() {
      _address = address;
      _balance = balance;
      _isLoading = false;
      _message = 'Wallet loaded successfully!';
    });

    // Save to session
    _storage.saveSession(privateKey);
  }

  Future<void> _sendTransaction() async {
    if (_address == null) {
      setState(() => _message = 'Please load wallet first');
      return;
    }

    final toAddress = _toAddressController.text.trim();
    final amount = double.tryParse(_amountController.text);

    if (toAddress.isEmpty || amount == null || amount <= 0) {
      setState(() => _message = 'Invalid address or amount');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = 'Sending transaction...';
    });

    final privateKey = _storage.loadSession();
    if (privateKey == null) {
      setState(() {
        _isLoading = false;
        _message = 'Session expired, please reload wallet';
      });
      return;
    }

    final result = await _walletService.sendTransaction(
      _rpcUrl,
      _rpcUser,
      _rpcPassword,
      privateKey,
      _address!,
      toAddress,
      amount,
    );

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _message = 'Transaction sent! TXID: ${result['txid']}';
        _toAddressController.clear();
        _amountController.clear();
        // Refresh balance
        _loadWallet();
      } else {
        _message = 'Error: ${result['message']}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF0A0A0A),
              const Color(0xFF1A1A1A),
              const Color(0xFF2A2A2A),
            ],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  const Text(
                    'Bitcoin Silver',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC0C0C0),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Web Wallet',
                    style: TextStyle(fontSize: 18, color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Load Wallet Section
                  if (_address == null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Load Wallet',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _privateKeyController,
                              decoration: const InputDecoration(
                                labelText: 'Private Key (WIF)',
                                border: OutlineInputBorder(),
                                hintText: 'Enter your private key...',
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _loadWallet,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                                backgroundColor: const Color(0xFFC0C0C0),
                                foregroundColor: Colors.black,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator()
                                  : const Text('Load Wallet', style: TextStyle(fontSize: 16)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Wallet Info
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Your Wallet',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            const Text('Balance', style: TextStyle(color: Colors.white54)),
                            Text(
                              '${_balance.toStringAsFixed(8)} BTCS',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFC0C0C0)),
                            ),
                            const SizedBox(height: 16),
                            const Text('Address', style: TextStyle(color: Colors.white54)),
                            SelectableText(
                              _address!,
                              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 16),
                            // QR Code
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                color: Colors.white,
                                child: QrImageView(
                                  data: _address!,
                                  size: 200,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Send Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Send BTCS',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _toAddressController,
                              decoration: const InputDecoration(
                                labelText: 'Recipient Address',
                                border: OutlineInputBorder(),
                                hintText: 'bs1...',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _amountController,
                              decoration: const InputDecoration(
                                labelText: 'Amount (BTCS)',
                                border: OutlineInputBorder(),
                                hintText: '0.00000000',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _sendTransaction,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                                backgroundColor: const Color(0xFFC0C0C0),
                                foregroundColor: Colors.black,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator()
                                  : const Text('Send Transaction', style: TextStyle(fontSize: 16)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Message
                  if (_message.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _message.contains('Error') || _message.contains('Invalid')
                            ? Colors.red.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _message,
                        style: TextStyle(
                          color: _message.contains('Error') || _message.contains('Invalid')
                              ? Colors.red
                              : Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Security Warning
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(height: 8),
                        Text(
                          'Security Warning',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Web wallets are less secure. Only use for small amounts. Private key is stored in browser session (cleared when you close the tab).',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
