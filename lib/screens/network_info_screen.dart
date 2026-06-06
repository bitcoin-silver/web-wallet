import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';

class NetworkInfoScreen extends StatefulWidget {
  const NetworkInfoScreen({super.key});

  @override
  State<NetworkInfoScreen> createState() => _NetworkInfoScreenState();
}

class _NetworkInfoScreenState extends State<NetworkInfoScreen> {
  Map<String, dynamic>? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchInfo();
  }

  Future<void> _fetchInfo() async {
    setState(() => _loading = true);
    final provider = context.read<WalletProvider>();
    final info = await provider.getNetworkInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Information'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _fetchInfo,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _info == null
              ? const Center(child: Text('Failed to load network information'))
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildSectionTitle('Blockchain'),
                    _buildInfoCard([
                      _buildInfoRow('Blocks', _info!['blocks'].toString()),
                      _buildInfoRow('Difficulty', _formatDifficulty(_info!['difficulty'])),
                      _buildInfoRow('Network Hashrate', _formatHashrate(_info!['networkhashps'])),
                      _buildInfoRow('Median Time', _formatTime(_info!['mediantime'])),
                    ]),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Mempool'),
                    _buildInfoCard([
                      _buildInfoRow('Transactions', _info!['mempool_size'].toString()),
                      _buildInfoRow('Size', _formatBytes(_info!['mempool_bytes'])),
                    ]),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Network'),
                    _buildInfoCard([
                      _buildInfoRow('Connections', _info!['connections'].toString()),
                      _buildInfoRow('Version', _info!['version'].toString()),
                      _buildInfoRow('Subversion', _info!['subversion'].toString()),
                    ]),
                  ],
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accentColor,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDifficulty(dynamic difficulty) {
    if (difficulty == null) return 'N/A';
    final formatter = NumberFormat.compact();
    return formatter.format(difficulty);
  }

  String _formatHashrate(dynamic hashrate) {
    if (hashrate == null) return 'N/A';
    double rate = (hashrate as num).toDouble();
    if (rate > 1e18) return '${(rate / 1e18).toStringAsFixed(2)} EH/s';
    if (rate > 1e15) return '${(rate / 1e15).toStringAsFixed(2)} PH/s';
    if (rate > 1e12) return '${(rate / 1e12).toStringAsFixed(2)} TH/s';
    if (rate > 1e9) return '${(rate / 1e9).toStringAsFixed(2)} GH/s';
    if (rate > 1e6) return '${(rate / 1e6).toStringAsFixed(2)} MH/s';
    if (rate > 1e3) return '${(rate / 1e3).toStringAsFixed(2)} KH/s';
    return '${rate.toStringAsFixed(2)} H/s';
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return 'N/A';
    int b = bytes as int;
    if (b > 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (b > 1024) return '${(b / 1024).toStringAsFixed(2)} KB';
    return '$b Bytes';
  }
}
