class Config {
  // LiveCoinWatch API Configuration (Price Data Source)
  static const String liveCoinWatchUrl = 'https://api.livecoinwatch.com/coins/single';
  static const String liveCoinWatchApiKey = String.fromEnvironment('LIVECOINWATCH_API_KEY', defaultValue: '');
  static const String sessionEncryptionSecretHex = String.fromEnvironment('SESSION_ENCRYPTION_SECRET_HEX', defaultValue: '');
  static const String btcsCode = '____BTCS';

  // Default RPC proxy. It can only be replaced from the settings UI.
  static const String defaultRpcUrl = 'https://bitcoinsilver.eu/btcs-rpc';

  // BTCS mainnet genesis block hash (consensus.hashGenesisBlock in chainparams).
  // A custom endpoint must report the same hash for block 0.
  static const String btcsGenesisHash =
      '00000ea8e97e04892a03df35947ff0c4df705723f5b18be7cc6456ed16e9788e';

}