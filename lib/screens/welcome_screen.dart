import 'package:flutter/material.dart';
import 'setup_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/footer_widget.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                        _buildOptionCard(
                          context,
                          title: 'Seed Phrase Wallet',
                          description: 'Recommended. Modern 12 or 24-word recovery phrase. Secure and easy to backup.',
                          icon: Icons.vpn_key_rounded,
                          color: AppTheme.primaryColor,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SetupScreen(useSeed: true)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildOptionCard(
                          context,
                          title: 'Legacy WIF Wallet',
                          description: 'Load an existing wallet using a raw Private Key (WIF).',
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppTheme.secondaryColor,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SetupScreen(useSeed: false)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Your keys never leave your browser.',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
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
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor.withValues(alpha: 0.5),
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
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}
