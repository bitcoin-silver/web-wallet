import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
      ],
      child: const BTCSWebWallet(),
    ),
  );
}

class BTCSWebWallet extends StatelessWidget {
  const BTCSWebWallet({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BTCS Web-Wallet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Consumer<WalletProvider>(
        builder: (context, walletProvider, _) {
          if (walletProvider.isLoaded) {
            return const DashboardScreen();
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}
