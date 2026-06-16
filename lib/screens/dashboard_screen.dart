import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';
import '../models/wallet_model.dart';
import '../models/transaction_model.dart';
import '../services/price_service.dart';
import 'network_info_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  late Timer _priceUpdateTimer;
  PriceData? _priceData;
  bool _priceLoading = true;
  final PriceService _priceService = PriceService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchPrice();
    _priceUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchPrice());
  }

  Future<void> _fetchPrice() async {
    final price = await _priceService.getBTCSPrice();
    if (mounted) {
      setState(() {
        _priceData = price;
        _priceLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _priceUpdateTimer.cancel();
    _tabController.dispose();
    _toController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();
    final wallet = provider.wallet!;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar (Desktop)
          if (MediaQuery.of(context).size.width > 900)
            _buildSidebar(provider),
          
          // Main Content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.backgroundColor, AppTheme.surfaceColor],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      _buildTopBar(wallet, provider),
                      // 🌐 Dynamic Global Message / Connection Banner Area
                      if (provider.message.isNotEmpty)
                        Padding(
                          padding: provider.message.contains('⚠️')
                              ? EdgeInsets.zero // Span full width across the content panel for connection drops
                              : const EdgeInsets.symmetric(horizontal: 24, vertical: 8), // Standard padding for actions
                          child: provider.message.contains('⚠️')
                              ? Container(
                                  width: double.infinity,
                                  color: Colors.amber.shade900,
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          provider.message,
                                          style: const TextStyle(
                                            color: Colors.white, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _buildMessage(provider.message), // Fallback to your custom message styling for normal info
                        ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildAssetsTab(wallet, provider),
                            _buildSendTab(provider),
                            _buildReceiveTab(wallet),
                            _buildSettingsTab(provider),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width <= 900
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.account_balance_wallet_rounded), text: 'Assets'),
                Tab(icon: Icon(Icons.send_rounded), text: 'Send'),
                Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Receive'),
                Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
              ],
            )
          : null,
    );
  }

  Widget _buildSidebar(WalletProvider provider) {
    return Material(
      color: Colors.black.withValues(alpha: 0.2),
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/logo_btcs.png', height: 200),
            const SizedBox(height: 60),
            _buildSidebarItem(0, Icons.account_balance_wallet_rounded, 'Assets'),
            _buildSidebarItem(1, Icons.send_rounded, 'Send'),
            _buildSidebarItem(2, Icons.qr_code_scanner_rounded, 'Receive'),
            _buildSidebarItem(3, Icons.settings_rounded, 'Settings'),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Support', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
            ListTile(
              onTap: () async {
                final Uri emailUri = Uri(
                  scheme: 'mailto',
                  path: 'info@bitcoinsilver.top',
                );
                if (await canLaunchUrl(emailUri)) {
                  await launchUrl(emailUri);
                }
              },
              leading: const Icon(Icons.email_rounded, size: 18, color: Colors.white38),
              title: const Text('info@bitcoinsilver.top', style: TextStyle(fontSize: 14, color: Colors.white54)),
            ),
            const SizedBox(height: 20),
            ListTile(
              onTap: provider.logout,
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label) {
    final isSelected = _tabController.index == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        onTap: () => setState(() => _tabController.index = index),
        selected: isSelected,
        leading: Icon(icon, color: isSelected ? AppTheme.primaryColor : Colors.white54),
        title: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      ),
    );
  }

  Widget _buildTopBar(WalletModel wallet, WalletProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wallet.type == WalletType.seed ? 'Modern Seed Phrase Wallet' : 'Legacy WIF Wallet',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.circle, color: Colors.green, size: 8),
                  const SizedBox(width: 8),
                  const Text('Mainnet', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () {
              provider.refreshBalance();
              setState(() {
                  _priceLoading = true;
                  _priceData = null;
              });
              _fetchPrice();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Balance',
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: message.contains('❌')
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: message.contains('❌')
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: message.contains('❌') ? Colors.redAccent : Colors.greenAccent,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAssetsTab(WalletModel wallet, WalletProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBalanceCard(wallet),
          const SizedBox(height: 40),
          const Text('Your Assets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildAssetItem('BTCS', 'Bitcoin Silver', wallet.balance, 'assets/logo_btcs.png'),
          // ── Transaction History ──────────────────────────────────────────
          const SizedBox(height: 40),
          _buildTransactionHistory(provider),
          // ── Migration Card ──────────────────────────────────────────
          if (wallet.type == WalletType.wif) ...[
            const SizedBox(height: 40),
            _buildMigrationCard(provider),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceCard(WalletModel wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: wallet.hasPending
              ? [Colors.orange.shade800, Colors.orange.shade600]
              : [const Color(0xFF1A3A5C), const Color(0xFF0D2137)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (wallet.hasPending ? Colors.orange : AppTheme.primaryColor).withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: label + pending badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                        if (wallet.hasPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.history_toggle_off_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'PENDING',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${wallet.totalBalance.toStringAsFixed(2)} BTCS',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (wallet.hasPending) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Confirmed: ${wallet.balance.toStringAsFixed(2)} BTCS',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const Text(
                        'Note: You have unconfirmed transactions.\nPlease wait ~10 min for a block confirmation.',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right: price widget
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Tooltip(
                  message: _priceData != null
                      ? 'Price updated from LiveCoinWatch\n'
                          '• 24h change: ${_priceData!.changePercent24h.toStringAsFixed(2)}%'
                      : 'Price data unavailable',
                  child: _buildFloatingPriceWidget(wallet.totalBalance),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildActionButton(Icons.arrow_upward_rounded, 'Send', () => _tabController.index = 1, tooltip: 'Send coins'),
              const SizedBox(width: 12),
              _buildActionButton(Icons.arrow_downward_rounded, 'Receive', () => _tabController.index = 2, tooltip: 'Receive coins'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingPriceWidget(double btcsBalance) {
    final usdBalance = _priceData != null ? btcsBalance * _priceData!.price : 0.0;
    
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'BTCS Price',
              style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            if (_priceLoading)
              const SizedBox(
                width: 60,
                height: 20,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ),
              )
            else if (_priceData != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${_priceData!.price.toStringAsFixed(6)} \$',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _priceData!.changePercent24h >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: _priceData!.changePercent24h >= 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_priceData!.changePercent24h.abs().toStringAsFixed(2)} %',
                        style: TextStyle(
                          color: _priceData!.changePercent24h >= 0
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Colors.white24),
                  const SizedBox(height: 8),
                  const Text(
                    'Portfolio Value',
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${usdBalance.toStringAsFixed(2)} \$',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              const Text(
                'data unavailable',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }

Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, {String? tooltip}) {
  return Tooltip(
    message: tooltip ?? label,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );
}

  Widget _buildAssetItem(String symbol, String name, double balance, String iconPath) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppTheme.backgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset(iconPath),
          ),
        ),
        title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(name),
        trailing: Text(
          balance.toStringAsFixed(8),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildMigrationCard(WalletProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.orange),
              SizedBox(width: 12),
              Text(
                'Migrate to Seed Phrase',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'You are using a legacy WIF wallet. Upgrade to a Seed Phrase wallet for better security and easier backup.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: provider.isLoading ? null : () => _showMigrationDialog(context, provider),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
            child: const Text('Start Migration (Sweep)'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Transaction History
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTransactionHistory(WalletProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Transaction History',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (provider.isLoadingTxs)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh history',
                onPressed: provider.fetchTransactions,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.isLoadingTxs && provider.transactions.isEmpty)
          ..._buildTxShimmer()
        else if (provider.transactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_rounded,
                    size: 48, color: Colors.white24),
                const SizedBox(height: 12),
                const Text(
                  'No transactions yet',
                  style: TextStyle(color: Colors.white38, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your transaction history will appear here.',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ],
            ),
          )
        else ...[
          ...provider.visibleTransactions
              .map((tx) => _buildTransactionCard(tx)),
          if (provider.hasMoreTransactions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: provider.loadMoreTransactions,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Load More Transactions'),
                ),
              ),
            ),
        ]
      ],
    );
  }

  List<Widget> _buildTxShimmer() {
    return List.generate(
      4,
      (i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx) {
    final isSent = tx.direction == TxDirection.sent;
    final isSelf = tx.direction == TxDirection.selfTransfer;
    final Color dirColor = isSelf
        ? Colors.blueAccent
        : isSent
            ? Colors.redAccent
            : Colors.greenAccent;
    final IconData dirIcon = isSelf
        ? Icons.swap_horiz_rounded
        : isSent
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;
    final String dirLabel = isSelf ? 'Self' : isSent ? 'Sent' : 'Received';
    final String amountStr =
        '${isSent ? '-' : '+'}${tx.amount.toStringAsFixed(3)} BTCS';

    // Relative timestamp
    String timeLabel = 'Pending';
    if (tx.timestamp != null) {
      final now = DateTime.now();
      final diff = now.difference(tx.timestamp!);
      if (diff.inMinutes < 60) {
        timeLabel = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeLabel = '${diff.inHours}h ago';
      } else {
        timeLabel = '${diff.inDays}d ago';
      }
    }

    final explorerUrl =
        'https://explorer.bitcoinsilver.top/tx/${tx.txid}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => launchUrl(Uri.parse(explorerUrl),
            mode: LaunchMode.externalApplication),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Direction icon circle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: dirColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(dirIcon, color: dirColor, size: 20),
              ),
              const SizedBox(width: 14),

              // TXID + timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          dirLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: dirColor,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildTxBadge(tx),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          tx.shortTxid,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: tx.txid));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('TXID copied'),
                                  duration: Duration(seconds: 2)),
                            );
                          },
                          child: const Icon(Icons.copy_rounded,
                              size: 12, color: Colors.white24),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Amount + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountStr,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelf ? Colors.white70 : dirColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),

              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded,
                  size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTxBadge(TransactionModel tx) {
    if (!tx.isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: const Text(
          'PENDING',
          style: TextStyle(
              fontSize: 9,
              color: Colors.orange,
              fontWeight: FontWeight.bold),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Confirmed',
        style: const TextStyle(
            fontSize: 9, color: Colors.greenAccent, fontWeight: FontWeight.bold),
      ),
    );
  }

int _migrationSeedWords = 12;

void _showMigrationDialog(BuildContext context, WalletProvider provider) {
  final isEmpty = provider.wallet!.balance <= 0.00001;
  final dashboardContext = context;

  showDialog(
    context: dashboardContext,
    builder: (dialogContext) => StatefulBuilder(
      builder: (statefulContext, setDialogState) => AlertDialog(
        title: isEmpty
            ? const Text('Switch to Seed Phrase')
            : Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 12),
                  Expanded(child: Text('Confirm Migration')),
                ],
              ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEmpty
                          ? 'NOTICE: This will generate a NEW seed phrase. No funds will be moved. BACKUP the generated seed phrase IMMEDIATELY ! after migration.'
                          : 'WARNING: This will MOVE ALL FUNDS to a NEW address. BACKUP the generated seed phrase IMMEDIATELY ! \n This action is irreversible. If you FAIL TO BACKUP the new seed phrase, you will LOSE ACCESS to your funds FOREVER.',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isEmpty
                  ? 'Your current wallet is empty. We will simply generate a NEW seed phrase wallet for you to use going forward.'
                  : 'This will generate a NEW seed phrase and send ALL your funds to the new address. '
                      'You MUST backup the new seed phrase immediately after migration.\n\n'
                      'A small network fee will apply.',
            ),
            const SizedBox(height: 20),
            const Text('Choose New Seed Length:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('12 Words'),
                  selected: _migrationSeedWords == 12,
                  onSelected: (selected) {
                    if (selected) setDialogState(() => _migrationSeedWords = 12);
                  },
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('24 Words'),
                  selected: _migrationSeedWords == 24,
                  onSelected: (selected) {
                    if (selected) setDialogState(() => _migrationSeedWords = 24);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await provider.migrateToSeed(words: _migrationSeedWords);
              if (success && dashboardContext.mounted) {
                _showBackupDialog(dashboardContext, provider);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isEmpty ? AppTheme.primaryColor : Colors.orange,
              foregroundColor: isEmpty ? Colors.white : Colors.black,
            ),
            child: Text(isEmpty ? 'Generate Seed Wallet' : 'Generate Seed & Sweep'),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSendTab(WalletProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Send Assets', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: _toController,
                decoration: const InputDecoration(
                  labelText: 'Recipient Address',
                  hintText: 'bs1...',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (BTCS)',
                  hintText: '0.00000000',
                  suffixIcon: TextButton(
                    onPressed: () => _amountController.text = provider.wallet!.balance.toString(),
                    child: const Text('MAX'),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: provider.isLoading ? null : () async {
                   final amount = double.tryParse(_amountController.text);
                   if (amount != null) {
                     final success = await provider.sendTransaction(_toController.text.trim(), amount);
                     if (success) {
                        _toController.clear();
                        _amountController.clear();
                     }
                   }
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 64)),
                child: provider.isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send Transaction', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiveTab(WalletModel wallet) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const Text('Receive BTCS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: wallet.address,
                size: 260,
              ),
            ),
            const SizedBox(height: 40),
            const Text('Your Address', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: SelectableText(
                wallet.address,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wallet.address));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied to clipboard'), duration: Duration(seconds: 2)),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy to Clipboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab(WalletProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        ListTile(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NetworkInfoScreen()),
          ),
          title: const Text('Network'),
          subtitle: const Text('Mainnet (https://bitcoinsilver.top/)'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(),
        ListTile(
          title: const Text('Wallet Type'),
          subtitle: Text(provider.wallet!.type == WalletType.seed ? 'Seed Phrase' : 'WIF Private Key'),
        ),
        const Divider(),
        ListTile(
          onTap: () => _showBackupDialog(context, provider),
          title: const Text('Backup Wallet'),
          subtitle: const Text('View your seed phrase or private key'),
          trailing: const Icon(Icons.security_rounded),
        ),
        const Divider(),
        ListTile(
          onTap: () => launchUrl(Uri.parse('https://bitcoinsilver.top/')),
          leading: const Icon(Icons.language_rounded, color: AppTheme.primaryColor),
          title: const Text('Official Website'),
          subtitle: const Text('bitcoinsilver.top'),
          trailing: const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white24),
        ),
        const Divider(),
        ListTile(
          onTap: () => launchUrl(Uri.parse('https://explorer.bitcoinsilver.top/')),
          leading: const Icon(Icons.search_rounded, color: AppTheme.primaryColor),
          title: const Text('Block Explorer'),
          subtitle: const Text('Check transactions and blocks'),
          trailing: const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white24),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: provider.logout,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), foregroundColor: Colors.redAccent),
          child: const Text('Logout & Clear Session'),
        ),
        const SizedBox(height: 10),
        const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('BTCS Web-Wallet version 2.4', 
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center
        ),      
       ),
      ],
    );
  }

  void _showBackupDialog(BuildContext context, WalletProvider provider) {
    final wallet = provider.wallet!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wallet Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CRITICAL: Never share these with anyone!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            if (wallet.type == WalletType.seed) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Seed Phrase:', style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: wallet.mnemonic!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seed phrase copied')));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(wallet.mnemonic ?? 'N/A', style: const TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 12),
              const Text(
                'The Seed Phrase above recovers your entire wallet, including all future addresses.',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Private Key (WIF):', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: wallet.privateKey));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Private key copied')));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(wallet.privateKey, style: const TextStyle(fontFamily: 'monospace')),
            ),
            if (wallet.type == WalletType.seed) ...[
              const SizedBox(height: 12),
              const Text(
                'This WIF key is derived from your seed and controls ONLY the current address. The Seed Phrase is the primary backup.',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
