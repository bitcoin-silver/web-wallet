import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
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

class SparklinePainter extends CustomPainter {
  final List<double> points;

  SparklinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs();

    List<Offset> offsets = List.generate(points.length, (i) {
      final x = i / (points.length - 1) * size.width;
      final y = range == 0
          ? size.height / 2
          : size.height - ((points[i] - min) / range * size.height * 0.8 + size.height * 0.1);
      return Offset(x, y);
    });

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, linePaint);

    // shadow fill below the line
    final fillPath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      fillPath.lineTo(o.dx, o.dy);
    }
    fillPath
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // dot at the latest point
    canvas.drawCircle(
      offsets.last,
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) => !listEquals(old.points, points);
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  static const int _satsPerBtcs = 100000000;

  late TabController _tabController;
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  late Timer _priceUpdateTimer;
  PriceData? _priceData;
  bool _priceLoading = true;
  bool _advancedSend = false;
  final PriceService _priceService = PriceService();
  bool? _addressValid; // null=unchecked/unknown, true=valid, false=invalid
  bool _isValidatingAddress = false;
  Timer? _addressDebounce;

  int _btcsToSats(double amount) => (amount * _satsPerBtcs).round();
  double _satsToBtcs(int sats) => sats / _satsPerBtcs;
  double _btcsKvBToSatVb(double btcsKvB) => btcsKvB / 0.00001;

  String _feeSourceLabel(WalletProvider provider) {
    switch (provider.feeRateSource) {
      case 'manual':
        return 'Manual';
      case 'clamped':
        return 'Clamped to Baseline';
      case 'baseline':
        return 'Node Baseline';
      case 'estimated':
        return 'Node Estimate';
      default:
        return 'Not Ready';
    }
  }

  Color _feeSourceColor(WalletProvider provider) {
    switch (provider.feeRateSource) {
      case 'manual':
        return Colors.amberAccent;
      case 'clamped':
        return Colors.orangeAccent;
      case 'baseline':
        return Colors.lightBlueAccent;
      case 'estimated':
        return Colors.greenAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchPrice();
    _priceUpdateTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchPrice());
    _amountController.addListener(() => setState(() {})); // triggers rebuild on type
    _tabController.addListener(() {
      if (_tabController.index == 1) { // 1 = Send tab
        final provider = context.read<WalletProvider>();
        provider.fetchFeeRate();
      }
    });
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
    _addressDebounce?.cancel();
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
                              : _buildMessage(provider.message), // Fallback to custom message styling for normal info
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
          // ── Balance Card ────────────────────────────────────────────
          _buildBalanceCard(wallet, provider),
          const SizedBox(height: 40),
          const Text('Your Assets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildAssetItem('BTCS', 'Bitcoin Silver', wallet.balance, 'assets/logo_btcs.png'),
          // ── Transaction History ─────────────────────────────────────
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

  List<double> _buildSparklinePoints(WalletModel wallet, List<TransactionModel> txs) {
    if (txs.isEmpty) return [];

    // take up to 10, oldest first
    final slice = txs.take(10).toList().reversed.toList();
    double running = wallet.totalBalance;

    // walk backwards from current balance to reconstruct history
    final points = <double>[running];
    for (final tx in slice) {
      if (tx.direction == TxDirection.sent) {
        running += tx.amount; // undo the send
      } else if (tx.direction == TxDirection.received) {
        running -= tx.amount; // undo the receive
      }
      points.insert(0, running.clamp(0, double.infinity));
    }
    return points;
  }

  Widget _buildBalanceCard(WalletModel wallet, WalletProvider provider) {
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
          const SizedBox(height: 20),
          Builder(builder: (_) {
            final pts = _buildSparklinePoints(wallet, provider.transactions);
            if (pts.length >= 2)
              return SizedBox(
                height: 40,
                width: double.infinity,
                child: CustomPaint(painter: SparklinePainter(pts)),
              );
            return const SizedBox.shrink();
          }),
          const SizedBox(height: 16),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.withValues(alpha: 1.0), foregroundColor: Colors.black),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
    if (tx.isPending) {
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

    final confirmationsLabel = tx.confirmations == 1
        ? '1 conf'
        : '${tx.confirmations} conf';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Text(
        confirmationsLabel,
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
                            ? 'NOTICE: This will generate a NEW seed phrase wallet including a NEW address. No funds will be moved. BACKUP the generated seed phrase IMMEDIATELY ! after migration.'
                            : 'WARNING: This will MOVE ALL FUNDS to a NEWLY GENERATED wallet address derived from your new seed phrase. BACKUP the generated seed phrase IMMEDIATELY ! \n This action is irreversible. If you FAIL TO BACKUP the new seed phrase, you will LOSE ACCESS to your funds FOREVER.',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isEmpty
                    ? 'Your current wallet is empty. We will simply generate a NEW seed phrase wallet including a NEW address for you to use going forward.'
                    : 'This will generate a NEW seed phrase and send ALL your funds to a NEWLY GENERATED wallet address. '
                        'The new address will be shown in the backup dialog after migration. '
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

                // Safety gate 1: require smart-fee availability before sweep migration.
                if (!isEmpty) {
                  await provider.fetchFeeRate();
                  if (!provider.feeRateReady) {
                    if (!dashboardContext.mounted) return;
                    _showMigrationBlockedDialog(
                      dashboardContext,
                      reason:
                          'Smart fee is unavailable. Migration cannot continue safely right now.\n\n'
                          'Details: ${provider.feeRateStatusMessage}',
                    );
                    return;
                  }
                }

                // Safety gate 2: pending transactions must be fully confirmed before migration.
                await provider.refreshBalance();
                final latestWallet = provider.wallet;
                if (latestWallet == null) return;
                if (latestWallet.hasPending) {
                  if (!dashboardContext.mounted) return;
                  _showMigrationBlockedDialog(
                    dashboardContext,
                    reason:
                        'Pending transactions detected. Migration cannot continue safely until all transactions are confirmed.\n\n'
                        'Confirmed: ${latestWallet.balance.toStringAsFixed(8)} BTCS\n'
                        'Unconfirmed: ${latestWallet.unconfirmedBalance.toStringAsFixed(8)} BTCS',
                  );
                  return;
                }

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

  void _showMigrationBlockedDialog(BuildContext context, {required String reason}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migration Blocked'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSendTab(WalletProvider provider) {
    final amountErr = _amountError(provider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Send Assets',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ToggleButtons(
                    isSelected: [!_advancedSend, _advancedSend],
                    onPressed: (index) {
                      final goAdvanced = index == 1;
                      setState(() => _advancedSend = goAdvanced);
                      if (goAdvanced) {
                        provider.fetchUtxosForCoinControl();
                      } else {
                        provider.resetCoinControl();
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Simple')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Advanced')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              _buildFeeStateBanner(provider),
              const SizedBox(height: 16),

              // Address field with live RPC validation
              TextField(
                controller: _toController,
                onChanged: (value) {
                  _addressDebounce?.cancel();
                  setState(() {
                    _addressValid = null;
                    _isValidatingAddress = value.isNotEmpty;
                  });
                  if (value.isEmpty) return;
                  _addressDebounce = Timer(const Duration(milliseconds: 700), () async {
                    final valid = await provider.validateAddress(value.trim());
                    setState(() {
                      _addressValid = valid;
                      _isValidatingAddress = false;
                    });
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Recipient Address',
                  hintText: 'bs1...',
                  suffixIcon: _isValidatingAddress
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _addressValid == null
                          ? null
                          : Icon(
                              _addressValid! ? Icons.check_circle : Icons.cancel,
                              color: _addressValid! ? Colors.green : Colors.red,
                            ),
                  errorText: _addressValid == false ? 'Invalid address' : null,
                ),
              ),
              const SizedBox(height: 20),

              // Amount field
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final text = newValue.text;
                    if (text.isEmpty) return newValue;
                    final valid = RegExp(r'^\d*\.?\d{0,8}$').hasMatch(text);
                    return valid ? newValue : oldValue;
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount (BTCS)',
                  hintText: '0.00000000',
                  errorText: _amountError(provider),
                  suffixIcon: TextButton(
                    onPressed: () {
                      _amountController.text = _advancedSend && provider.selectedUtxoCount > 0
                          ? provider.selectedUtxoTotal.toStringAsFixed(8)
                          : provider.wallet!.balance.toString();
                    },
                    child: const Text('MAX'),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              _buildFeeEstimate(provider),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: provider.isLoading
                        ? null
                        : () async {
                            final manualFeeRate = await _showManualFeeDialog(context);
                            if (manualFeeRate != null) {
                              provider.setManualFeeRate(manualFeeRate);
                            }
                          },
                    child: const Text('Set Manual Fee'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: provider.isFetchingFeeRate ? null : () => provider.fetchFeeRate(),
                    child: const Text('Use Node Fee'),
                  ),
                ],
              ),

              if (_advancedSend) ...[
                const SizedBox(height: 32),
                _buildUtxoSelector(provider),
              ],
              const SizedBox(height: 12),
              _buildSendPreview(provider),
              const SizedBox(height: 40),

              ElevatedButton(
                  onPressed: provider.isLoading 
                      || amountErr != null 
                      || _isValidatingAddress
                      || _toController.text.trim().isEmpty    
                      || _addressValid == false                
                      ? null
                      : () async {
                          provider.clearMessage();
                          final amount = double.tryParse(_amountController.text);
                          if (amount != null) {
                            // Keep send fee path identical to preview: use fetched rate when
                            // available, otherwise ask for manual fee before broadcast.
                            double? feeRateCoinPerKvB;
                            if (provider.feeRateReady) {
                              feeRateCoinPerKvB = provider.feeRate;
                            } else {
                              await provider.fetchFeeRate();
                              if (provider.feeRateReady) {
                                feeRateCoinPerKvB = provider.feeRate;
                              } else if (mounted) {
                                final manualFeeRate = await _showManualFeeDialog(context);
                                if (manualFeeRate == null) return;
                                provider.setManualFeeRate(manualFeeRate);
                                feeRateCoinPerKvB = manualFeeRate;
                              }
                            }

                            final preConfirm = await _showPreSendConfirmDialog(
                              context: context,
                              provider: provider,
                              toAddress: _toController.text.trim(),
                              amount: amount,
                            );
                            if (!preConfirm) return;

                            final result = await provider.sendTransaction(
                              _toController.text.trim(),
                              amount,
                              manualFeeRateCoinPerKb: feeRateCoinPerKvB,
                            );

                            if (result['success'] != true && result['requiresManualFee'] == true && mounted) {
                              final manualFeeRate = await _showManualFeeDialog(context);
                              if (manualFeeRate != null) {
                                provider.setManualFeeRate(manualFeeRate);
                                final retryResult = await provider.sendTransaction(
                                  _toController.text.trim(),
                                  amount,
                                  manualFeeRateCoinPerKb: manualFeeRate,
                                );
                                if (retryResult['success'] == true) {
                                  _resetSendForm(provider);
                                  if (mounted) {
                                    await _showPostSendAckDialog(
                                      context: context,
                                      txid: (retryResult['txid'] as String?) ?? '',
                                      amount: amount,
                                      fee: (retryResult['fee'] as num?)?.toDouble() ?? 0.0,
                                    );
                                  }
                                }
                              }
                              return;
                            }

                            if (result['success'] == true) {
                              _resetSendForm(provider);
                              if (mounted) {
                                await _showPostSendAckDialog(
                                  context: context,
                                  txid: (result['txid'] as String?) ?? '',
                                  amount: amount,
                                  fee: (result['fee'] as num?)?.toDouble() ?? 0.0,
                                );
                              }
                            }
                          }
                        },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 64)),
                child: provider.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send Transaction',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _amountError(WalletProvider provider) {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null) return 'Invalid number';
    if (value <= 0) return 'Amount must be greater than zero';
    if (value < 0.00000546) return 'Amount below dust threshold (0.00000546 BTCS)';
    if (_advancedSend && provider.selectedUtxoCount > 0 && value > provider.selectedUtxoTotal) {
      return 'Exceeds selected inputs (${provider.selectedUtxoTotal.toStringAsFixed(8)} BTCS)';
    }
    if (!_advancedSend && value > (provider.wallet?.balance ?? 0)) {
      return 'Exceeds available balance';
    }
    return null;
  }

  void _syncAmountToSelection(WalletProvider provider) {
    if (!_advancedSend) return;
    final total = provider.selectedUtxoTotal;
    _amountController.text = total > 0 ? total.toStringAsFixed(8) : '';
  }

  Widget _buildFeeStateBanner(WalletProvider provider) {
    final bool warning = !provider.feeRateReady;
    final Color color = warning ? Colors.orange : Colors.green;
    final IconData icon = warning ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.feeRateStatusMessage,
              style: TextStyle(fontSize: 12, color: warning ? Colors.orange.shade200 : Colors.green.shade200),
            ),
          ),
          if (warning)
            TextButton(
              onPressed: provider.isFetchingFeeRate ? null : () => provider.fetchFeeRate(),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Future<double?> _showManualFeeDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? error;
    bool satPerVb = true;

    const lowBtcsKvB = 0.00000226;
    const highBtcsKvB = 0.0004;
    const satVbToBtcsKvB = 0.00001;
    final lowSatVb = lowBtcsKvB / satVbToBtcsKvB;
    final highSatVb = highBtcsKvB / satVbToBtcsKvB;

    controller.text = lowSatVb.toStringAsFixed(4);

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manual Fee Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Automatic fee estimation is unavailable. Enter a manual fee rate to continue.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ToggleButtons(
                    isSelected: [satPerVb, !satPerVb],
                    onPressed: (index) {
                      setDialogState(() {
                        final nextSatVb = index == 0;
                        final parsed = double.tryParse(controller.text.trim());
                        if (parsed != null && parsed > 0 && nextSatVb != satPerVb) {
                          final converted = nextSatVb
                              ? parsed / satVbToBtcsKvB
                              : parsed * satVbToBtcsKvB;
                          controller.text = nextSatVb
                              ? converted.toStringAsFixed(4)
                              : converted.toStringAsFixed(8);
                        }
                        satPerVb = nextSatVb;
                        error = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('sat/vB'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('BTCS/kvB'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Low traffic: ${lowSatVb.toStringAsFixed(3)} sat/vB (${lowBtcsKvB.toStringAsFixed(8)} BTCS/kvB)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'High traffic: ${highSatVb.toStringAsFixed(3)} sat/vB (${highBtcsKvB.toStringAsFixed(8)} BTCS/kvB)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setDialogState(() {
                            controller.text = satPerVb
                              ? lowSatVb.toStringAsFixed(4)
                                : lowBtcsKvB.toStringAsFixed(8);
                            error = null;
                          });
                        },
                        child: const Text('Use Low'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          setDialogState(() {
                            controller.text = satPerVb
                              ? highSatVb.toStringAsFixed(4)
                                : highBtcsKvB.toStringAsFixed(8);
                            error = null;
                          });
                        },
                        child: const Text('Use High'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: satPerVb ? 'Fee rate (sat/vB)' : 'Fee rate (BTCS/kvB)',
                      hintText: satPerVb
                          ? 'e.g. ${lowSatVb.toStringAsFixed(4)}'
                          : 'e.g. ${lowBtcsKvB.toStringAsFixed(8)}',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final raw = double.tryParse(controller.text.trim());
                    if (raw == null || raw <= 0) {
                      setDialogState(() {
                        error = 'Enter a valid fee rate greater than zero.';
                      });
                      return;
                    }

                    final feeRateCoinPerKb = satPerVb ? (raw * satVbToBtcsKvB) : raw;
                    if (feeRateCoinPerKb <= 0) {
                      setDialogState(() {
                        error = 'Converted fee rate is invalid.';
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, feeRateCoinPerKb);
                  },
                  child: const Text('Use Fee Rate'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  void _resetSendForm(WalletProvider provider) {
    _toController.clear();
    _amountController.clear();
    setState(() {
      _addressValid = null;
      if (_advancedSend) _advancedSend = false;
    });
    provider.resetCoinControl();
  }

  Future<bool> _showPreSendConfirmDialog({
    required BuildContext context,
    required WalletProvider provider,
    required String toAddress,
    required double amount,
  }) async {
    final hasSelectedInputs = _advancedSend && provider.selectedUtxoCount > 0;
    final estimatedFee = hasSelectedInputs ? provider.estimatedFee : provider.estimatedSimpleFee;
    final feeSource = _feeSourceLabel(provider);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('To: $toAddress', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text('Amount: ${amount.toStringAsFixed(8)} BTCS'),
              const SizedBox(height: 4),
              Text('Estimated fee: ${estimatedFee.toStringAsFixed(8)} BTCS'),
              const SizedBox(height: 4),
              Text('Fee source: $feeSource'),
              const SizedBox(height: 4),
              Text(
                'Fee rate: ${provider.feeRate.toStringAsFixed(8)} BTCS/kvB '
                '(${_btcsKvBToSatVb(provider.feeRate).toStringAsFixed(2)} sat/vB)',
              ),
              if (hasSelectedInputs) ...[
                const SizedBox(height: 4),
                Text('Selected inputs: ${provider.selectedUtxoCount}'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Agree & Send'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _showPostSendAckDialog({
    required BuildContext context,
    required String txid,
    required double amount,
    required double fee,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Transaction Sent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount: ${amount.toStringAsFixed(8)} BTCS'),
              const SizedBox(height: 4),
              Text('Fee paid: ${fee.toStringAsFixed(8)} BTCS'),
              if (txid.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('TXID:'),
                const SizedBox(height: 4),
                SelectableText(
                  txid,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Acknowledge'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUtxoSelector(WalletProvider provider) {
    if (provider.isLoadingUtxos) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Scanning UTXOs...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (provider.availableUtxos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text('No confirmed UTXOs found.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Inputs  (${provider.availableUtxos.length} total)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                TextButton(onPressed: () {
                  provider.selectAllUtxos();
                  _syncAmountToSelection(provider);
                }, child: const Text('All')),
                TextButton(onPressed: () {
                  provider.clearUtxoSelection();
                  _syncAmountToSelection(provider);
                }, child: const Text('None')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Summary bar
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: provider.selectedUtxoCount > 0
              ? Container(
                  key: const ValueKey('summary'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        '${provider.selectedUtxoCount} input${provider.selectedUtxoCount > 1 ? 's' : ''}'
                        '  ·  ${provider.selectedUtxoTotal.toStringAsFixed(8)} BTCS',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                )
              : const SizedBox(key: ValueKey('empty')),
        ),

        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: const [
              SizedBox(width: 32, child: Text('#', style: TextStyle(fontSize: 12, color: Colors.grey))),
              Expanded(flex: 3, child: Text('TXID : vout', style: TextStyle(fontSize: 12, color: Colors.grey))),
              Expanded(flex: 2, child: Text('Amount', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.right)),
              SizedBox(width: 52, child: Text('Conf', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)),
              SizedBox(width: 36),
            ],
          ),
        ),

        // Fixed-height scrollable UTXO list
        SizedBox(
          height: 360,
          child: SingleChildScrollView(
            child: Column(
              children: provider.availableUtxos.asMap().entries.map((entry) {
                final i = entry.key;
                final utxo = entry.value;
                final key = '${utxo['txid']}:${utxo['vout']}';
                final isSelected = provider.selectedUtxoKeys.contains(key);
                final txid = utxo['txid'] as String;
                final txidShort = '${txid.substring(0, 8)}…${txid.substring(txid.length - 6)}:${utxo['vout']}';

                return InkWell(
                  onTap: () {
                    provider.toggleUtxo(key);
                    _syncAmountToSelection(provider);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber.withValues(alpha: 0.07)
                          : (i.isOdd ? Colors.white.withValues(alpha: 0.02) : Colors.transparent),
                      border: Border(
                        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            txidShort,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            (utxo['amount'] as num).toStringAsFixed(8),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${utxo['confirmations']}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) {
                              provider.toggleUtxo(key);
                              _syncAmountToSelection(provider);
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeeEstimate(WalletProvider provider) {
    final hasSelectedInputs = _advancedSend && provider.selectedUtxoCount > 0;
    final fee = hasSelectedInputs ? provider.estimatedFee : provider.estimatedSimpleFee;
    final label = hasSelectedInputs ? 'Est. fee' : 'Est. fee (typical tx)';

    if (provider.isFetchingFeeRate) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Text(
          'Fetching fee estimate...',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    if (fee <= 0) return const SizedBox.shrink();

    final feeRate = provider.feeRate;
    final feeRateSatVb = _btcsKvBToSatVb(feeRate);
    final feeSource = _feeSourceLabel(provider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                '$feeSource source',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${fee.toStringAsFixed(8)} BTCS',
                style: const TextStyle(fontSize: 13),
              ),
              if (hasSelectedInputs)
                Text(
                  provider.estimatedNetSend > 0
                      ? 'Net ${provider.estimatedNetSend.toStringAsFixed(8)} BTCS'
                      : 'Net —',
                  style: TextStyle(
                    fontSize: 13,
                    color: provider.estimatedNetSend > 0 ? Colors.white : Colors.red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Rate: ${feeRate.toStringAsFixed(8)} BTCS/kvB (${feeRateSatVb.toStringAsFixed(2)} sat/vB)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSendPreview(WalletProvider provider) {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) return const SizedBox.shrink();

    final hasSelectedInputs = _advancedSend && provider.selectedUtxoCount > 0;
    final fee = hasSelectedInputs ? provider.estimatedFee : provider.estimatedSimpleFee;

    final selectedInputsSats = hasSelectedInputs ? _btcsToSats(provider.selectedUtxoTotal) : 0;
    final autoSpendableSats = _btcsToSats(provider.wallet?.balance ?? 0.0);
    final amountSats = _btcsToSats(amount);
    final feeSats = _btcsToSats(fee);
    final expectedChangeSats = hasSelectedInputs
        ? (selectedInputsSats - amountSats - feeSats)
        : (autoSpendableSats - amountSats - feeSats);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transaction Preview',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Selected Inputs', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                hasSelectedInputs
                    ? '${_satsToBtcs(selectedInputsSats).toStringAsFixed(8)} BTCS'
                    : 'Auto',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Send Amount', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(amountSats).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated Fee', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(feeSats).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fee Source', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                _feeSourceLabel(provider),
                style: TextStyle(
                  color: _feeSourceColor(provider),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fee Rate', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${provider.feeRate.toStringAsFixed(8)} BTCS/kvB (${_btcsKvBToSatVb(provider.feeRate).toStringAsFixed(2)} sat/vB)',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expected Change', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(expectedChangeSats > 0 ? expectedChangeSats : 0).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ],
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
        SwitchListTile(
          value: provider.rememberSessionEnabled,
          onChanged: (value) async {
            await provider.setRememberSessionEnabled(value);
            if (!mounted) return;
            if (value && !provider.hasSessionEncryptionSecret) {
              _showSessionSecurityInfo(context, missingSecret: true);
            }
          },
          title: const Text('Remember Wallet On This Device'),
          subtitle: Text(
            provider.rememberSessionEnabled
                ? 'Enabled: encrypted wallet session is persisted in browser local storage.'
                : 'Disabled: you must re-enter keys/seed after logout or tab close.',
          ),
          secondary: const Icon(Icons.lock_outline_rounded),
        ),
        ListTile(
          onTap: () => _showSessionSecurityInfo(context),
          title: const Text('Session Persistence Security Notes'),
          subtitle: const Text('Read risks before enabling remembered session.'),
          trailing: const Icon(Icons.info_outline_rounded),
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
              child: Text('BTCS Web-Wallet version 2.7', 
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
              const Text('New Wallet Address:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        wallet.address,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: wallet.address));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('New wallet address copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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

  void _showSessionSecurityInfo(BuildContext context, {bool missingSecret = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remembered Session Security'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (missingSecret)
                const Text(
                  'SESSION_ENCRYPTION_SECRET_HEX is missing in your dart defines. Add a 64-char hex key before enabling this feature.',
                  style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                ),
              if (missingSecret) const SizedBox(height: 12),
              const Text('What this does:'),
              const SizedBox(height: 6),
              const Text('• Stores an encrypted wallet session in browser local storage.'),
              const Text('• Allows automatic wallet restore without re-entering seed/WIF.'),
              const SizedBox(height: 12),
              const Text('Security risks:'),
              const SizedBox(height: 6),
              const Text('• Any malware or malicious browser extension on this device may still extract data while unlocked.'),
              const Text('• Dart define secrets in a web app can be extracted from the shipped bundle; this is defense-in-depth, not absolute secrecy.'),
              const Text('• Shared/public computers should never enable remembered sessions.'),
              const SizedBox(height: 12),
              const Text(
                'Recommendation: keep this OFF for high-value wallets. Use hardware or offline storage for long-term holdings.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
