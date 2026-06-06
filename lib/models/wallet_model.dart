enum WalletType { wif, seed }

class WalletModel {
  final String address;
  final String privateKey; // WIF format for both types internally for signing
  final String? mnemonic;
  final WalletType type;
  final double balance;
  final double unconfirmedBalance;
  final bool isPending;

  WalletModel({
    required this.address,
    required this.privateKey,
    this.mnemonic,
    required this.type,
    this.balance = 0.0,
    this.unconfirmedBalance = 0.0,
    this.isPending = false,
  });

  bool get hasPending => isPending || unconfirmedBalance != 0;
  double get totalBalance => balance + unconfirmedBalance;

  WalletModel copyWith({
    String? address,
    String? privateKey,
    String? mnemonic,
    WalletType? type,
    double? balance,
    double? unconfirmedBalance,
    bool? isPending,
  }) {
    return WalletModel(
      address: address ?? this.address,
      privateKey: privateKey ?? this.privateKey,
      mnemonic: mnemonic ?? this.mnemonic,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      unconfirmedBalance: unconfirmedBalance ?? this.unconfirmedBalance,
      isPending: isPending ?? this.isPending,
    );
  }
}
