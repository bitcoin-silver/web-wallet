import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

const String btcsDisclaimerTitle = 'Disclaimer: ';
const String btcsDisclaimerSummaryText =
  'BitcoinSilver Web-Wallet is self-custodial software provided for technical and informational use. It is provided "as is" without warranties.';
const String btcsDisclaimerResponsibilityText =
  'You are solely responsible for protecting your seed phrase and WIF private key, and for complying with local laws and tax obligations.';
const String btcsDisclaimerText =
  'BTCS (Bitcoin Silver) is a fully decentralized, open-source cryptocurrency based on the Proof-of-Work algorithm. There is no corporate entity, no pre-sale and no developer allocation. This website is for technical and informational purposes only. The software is provided "as is", without warranty of any kind. Users are solely responsible for securing their private keys and seed phrases and for complying with applicable local laws and tax regulations. BTCS does not constitute a crypto-asset service under EU Regulation 2023/1114 (MiCA).';

class FooterWidget extends StatelessWidget {
  const FooterWidget({super.key});

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri)) {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: const Border(
          top: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1800),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildBrandSection()),
                        Expanded(child: _buildResourcesSection()),
                        Expanded(child: _buildCommunitySection()),
                        
                      ],
                    );
                  } else if (constraints.maxWidth > 600) {
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildBrandSection()),
                            Expanded(child: _buildResourcesSection()),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCommunitySection()),
                            
                          ],
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBrandSection(),
                        const SizedBox(height: 40),
                        _buildResourcesSection(),
                        const SizedBox(height: 40),
                        _buildCommunitySection(),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildDisclaimerSection(context),
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              _buildBottomSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.coins, color: AppTheme.accentColor, size: 28),
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.accentColor],
              ).createShader(bounds),
              child: const Text(
                'Bitcoin Silver',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Digital Silver for the Next Generation of Crypto Enthusiasts.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 24),
        _buildEmailLink(FontAwesomeIcons.envelope, 'info@bitcoinsilver.top'),
        const SizedBox(height: 12),],
    );
  }

  Widget _buildEmailLink(dynamic icon, String email) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launchUrl('mailto:$email'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: AppTheme.accentColor.withValues(alpha: 0.7), size: 14),
            const SizedBox(width: 10),
            Text(
              email,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesSection() {
    return _buildFooterColumn(
      title: 'Resources',
      icon: FontAwesomeIcons.layerGroup,
      links: [
        _FooterLink('Whitepaper', 'https://bitcoinsilver.top/whitepaper.pdf', icon: FontAwesomeIcons.fileLines),
        _FooterLink('BlockChain Explorer', 'https://explorer.bitcoinsilver.top/', icon: FontAwesomeIcons.magnifyingGlass),
        _FooterLink('GitHub', 'https://github.com/bitcoin-silver/web-wallet', icon: FontAwesomeIcons.github),
      ],
    );
  }

  Widget _buildCommunitySection() {
    return _buildFooterColumn(
      title: 'Community',
      icon: FontAwesomeIcons.users,
      links: [
        _FooterLink('Discord', 'https://discord.com/invite/Pbt2R55XBt', icon: FontAwesomeIcons.discord),
        _FooterLink('Telegram', 'https://t.me/official_bitcoinsilver', icon: FontAwesomeIcons.telegram),
        _FooterLink('Twitter / X', 'https://x.com/Official_BTCS', icon: FontAwesomeIcons.xTwitter),
      ],
    );
  }

  Widget _buildFooterColumn({
    required String title,
    required dynamic icon,
    required List<_FooterLink> links,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: AppTheme.accentColor, size: 18),
            const SizedBox(width: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...links.map((link) => Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _launchUrl(link.url),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(link.icon, color: Colors.white.withValues(alpha: 0.4), size: 16),
                  const SizedBox(width: 12),
                  Text(
                    link.name,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildBottomSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;
        
        final copyright = Text(
          '© 2026 BTCS — Open source cryptocurrency.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 13,
          ),
        );

        final origin = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            Text(
              'Built with',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
            ),
            const SizedBox(width: 6),
            const FaIcon(FontAwesomeIcons.bolt, color: Colors.amber, size: 12),
            const SizedBox(width: 6),
            Text(
              'by the Bitcoin Silver community.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

        final links = Wrap(
          spacing: 20,
          runSpacing: 10,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _buildBottomLink('Wallets', FontAwesomeIcons.wallet),
            _buildBottomLink('Features', FontAwesomeIcons.star),
            _buildBottomLink('Specs', FontAwesomeIcons.listCheck),
            _buildBottomLink('Downloads', FontAwesomeIcons.download),
          ],
        );

        if (isMobile) {
          return Column(
            children: [
              links,
              const SizedBox(height: 24),
              origin,
              const SizedBox(height: 12),
              copyright,
            ],
          );
        }

        return Row(
          children: [
            copyright,
            const Spacer(),
            origin,
            const Spacer(),
            links,
          ],
        );
      },
    );
  }

  Widget _buildDisclaimerSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            btcsDisclaimerTitle,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            btcsDisclaimerSummaryText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            btcsDisclaimerResponsibilityText,
            style: TextStyle(
              color: Colors.redAccent.withValues(alpha: 0.9),
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white54,
                title: Text(
                  'Read full disclaimer text',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Text(
                    btcsDisclaimerText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }  

  Widget _buildBottomLink(String label, dynamic icon) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launchUrl('https://bitcoinsilver.top/#${label.toLowerCase()}'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: Colors.white.withValues(alpha: 0.2), size: 12),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink {
  final String name;
  final String url;
  final dynamic icon;

  _FooterLink(this.name, this.url, {required this.icon});
}
