import 'package:flutter/material.dart';
import 'setup_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/footer_widget.dart';
import '../services/storage_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final StorageService _storage = StorageService();
  bool _agreementGateEnabled = true;
  bool _hasAgreed = false;

  @override
  void initState() {
    super.initState();
    final hasAcceptedDisclaimer = _storage.loadLegalDisclaimerAccepted();

    _agreementGateEnabled = true;
    _hasAgreed = hasAcceptedDisclaimer;
  }

  void _handleAgreementChanged(bool? value) {
    final agreed = value ?? false;
    setState(() {
      _hasAgreed = agreed;
    });
    _storage.saveLegalDisclaimerAccepted(agreed);
  }

  void _openSetup(bool useSeed) {
    if (_agreementGateEnabled && !_hasAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please review and accept the legal disclaimer before continuing.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SetupScreen(useSeed: useSeed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canProceed = !_agreementGateEnabled || _hasAgreed;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.backgroundColor,
              AppTheme.surfaceColor,
              AppTheme.backgroundColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Main Content
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Hero(
                          tag: 'logo',
                          child: Image.asset('assets/logo.png', height: 160),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Bitcoin Silver',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'SECURE WEB WALLET',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_agreementGateEnabled) ...[
                          _buildDisclaimerSection(),
                          const SizedBox(height: 20),
                        ],
                        _buildOptionCard(
                          context,
                          title: 'Seed Phrase Wallet',
                          description: 'Recommended. Modern 12 or 24-word recovery phrase. Secure and easy to backup.',
                          icon: Icons.vpn_key_rounded,
                          color: AppTheme.primaryColor,
                          enabled: canProceed,
                          onTap: () => _openSetup(true),
                        ),
                        const SizedBox(height: 20),
                        _buildOptionCard(
                          context,
                          title: 'Legacy WIF Wallet',
                          description: 'Load an existing wallet using a raw Private Key (WIF).',
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppTheme.secondaryColor,
                          enabled: canProceed,
                          onTap: () => _openSetup(false),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Your keys never leave your browser.',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text('BTCS Web-Wallet version 2.5', 
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                                textAlign: TextAlign.center
                          ),      
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Footer
              const FooterWidget(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: enabled
                ? AppTheme.surfaceColor.withValues(alpha: 0.5)
                : AppTheme.surfaceColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: enabled ? 0.6 : 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                enabled ? Icons.chevron_right_rounded : Icons.lock_outline,
                color: Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimerSection() {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            btcsLegalDisclaimerTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            btcsLegalSummaryText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Material(
            type: MaterialType.transparency,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white54,
                title: Text(
                  'Read full legal text',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      btcsLegalDisclaimerText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Wallet Usage and Security Responsibility',
            style: TextStyle(
              color: AppTheme.accentColor.withValues(alpha: 0.95),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This wallet is self-custodial. BitcoinSilver cannot recover lost credentials. Keep your seed phrase and WIF private key offline, confidential, and backed up in secure locations. Anyone with access to these credentials can irreversibly control your funds.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child: const Text(
              'Critical: You are solely responsible for keeping your seed phrase and WIF secure.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasAgreed,
              onChanged: _handleAgreementChanged,
              activeColor: AppTheme.primaryColor,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'I have read and agree to the legal disclaimer and understand my responsibility to secure my seed phrase and WIF.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
