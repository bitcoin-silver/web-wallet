import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';

class SetupScreen extends StatefulWidget {
  final bool useSeed;
  const SetupScreen({super.key, required this.useSeed});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isGenerating = false;
  String? _generatedMnemonic;
  String? _generatedWif;
  bool _hasConfirmedBackup = false;
  int _seedWordCount = 12;
  bool _isProcessing = false;

  Future<void> _handleGenerate() async {
    setState(() {
      _isProcessing = true;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    final provider = context.read<WalletProvider>();
    
    try {
      if (widget.useSeed) {
        final walletData = await provider.walletService.generateNewSeedWallet(words: _seedWordCount);
        if (mounted) {
          setState(() {
            _generatedMnemonic = walletData['mnemonic'];
            _generatedWif = walletData['privateKey'];
            _isGenerating = true; // Only switch view when calculations are complete
          });
        }
      } else {
        final walletData = provider.walletService.generateNewWallet();
        if (mounted) {
          setState(() {
            _generatedWif = walletData['privateKey'];
            _isGenerating = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handleLoad() {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    final provider = context.read<WalletProvider>();
    if (widget.useSeed) {
      provider.loadSeedWallet(input).then((success) {
        if (success && provider.isLoaded && mounted) Navigator.pop(context);
      });
    } else {
      provider.loadWifWallet(input).then((success) {
        if (success && provider.isLoaded && mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _handleFinalize() async {
    if (widget.useSeed && !_hasConfirmedBackup) return;

    final provider = context.read<WalletProvider>();
    bool success = false;
    
    if (widget.useSeed) {
      if (_generatedMnemonic == null) return;
      success = await provider.loadSeedWallet(_generatedMnemonic!);
    } else {
      if (_generatedWif == null) return;
      success = await provider.loadWifWallet(_generatedWif!);
    }

    if (success && provider.isLoaded && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
             provider.logout();
             Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.useSeed ? 'Seed Phrase Wallet' : 'Legacy WIF Wallet',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                if (!_isGenerating) ...[
                  _buildLoadSection(provider),
                  const SizedBox(height: 40),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: Colors.white38)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 40),
                  _buildGenerateSection(provider),
                ] else ...[
                  _buildBackupSection(),
                ],
                if (provider.message.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    provider.message,
                    style: TextStyle(
                      color: provider.message.contains('❌') ? Colors.red : Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 40),
                const Text(
                  'BTCS Web-Wallet version 2.7',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadSection(WalletProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.useSeed ? 'Restore from Seed' : 'Import Private Key',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              maxLines: widget.useSeed ? 3 : 1,
              decoration: InputDecoration(
                hintText: widget.useSeed 
                  ? 'Enter your 12 or 24 word seed phrase...'
                  : 'Enter your WIF private key...',
                helperText: widget.useSeed 
                  ? null 
                  : 'Note: Only BTCS network WIF keys are supported.',
                helperStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: provider.isLoading ? null : _handleLoad,
              child: provider.isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Load Wallet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateSection(WalletProvider provider) {
    if (widget.useSeed) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Seed Length: '),
              ChoiceChip(
                label: const Text('12 Words'),
                selected: _seedWordCount == 12,
                onSelected: (selected) {
                  if (selected) setState(() => _seedWordCount = 12);
                },
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('24 Words'),
                selected: _seedWordCount == 24,
                onSelected: (selected) {
                  if (selected) setState(() => _seedWordCount = 24);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _handleGenerate,
            icon: _isProcessing
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Generate New Seed Phrase'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(20),
              side: const BorderSide(color: AppTheme.primaryColor),
              foregroundColor: AppTheme.primaryColor,
              minimumSize: const Size(double.infinity, 60),
            ),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: _isProcessing ? null : _handleGenerate,
      icon: _isProcessing
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.add_circle_outline_rounded),
      label: const Text('Generate New Private Key'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(20),
        side: const BorderSide(color: AppTheme.primaryColor),
        foregroundColor: AppTheme.primaryColor,
        minimumSize: const Size(double.infinity, 60),
      ),
    );
  }

  Widget _buildBackupSection() {
    final data = widget.useSeed ? _generatedMnemonic : _generatedWif;
    final provider = context.watch<WalletProvider>();
    
    return Column(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 64),
        const SizedBox(height: 16),
        const Text(
          'BACKUP YOUR KEYS',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange),
        ),
        const SizedBox(height: 8),
        const Text(
          'Write down these words/key and store them safely. If you lose them, your funds are gone forever.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              if (widget.useSeed)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: data!.split(' ').asMap().entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        '${entry.key + 1}. ${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    );
                  }).toList(),
                )
              else
                SelectableText(
                  data!,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: data));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy to Clipboard'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        if (widget.useSeed)
          CheckboxListTile(
            value: _hasConfirmedBackup,
            onChanged: (v) => setState(() => _hasConfirmedBackup = v ?? false),
            title: const Text('I have written down my seed phrase and stored it securely.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: provider.isLoading 
              ? null 
              : ((widget.useSeed && !_hasConfirmedBackup) ? null : _handleFinalize),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 60),
          ),
          child: provider.isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('I\'M READY, LET\'S GO'),
        ),
      ],
    );
  }
}