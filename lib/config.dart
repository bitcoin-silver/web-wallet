class Config {
  // LiveCoinWatch API Configuration (Price Data Source)
  static const String liveCoinWatchUrl = 'https://api.livecoinwatch.com/coins/single';
  static const String liveCoinWatchApiKey = String.fromEnvironment('LIVECOINWATCH_API_KEY', defaultValue: '');
  static const String sessionEncryptionSecretHex = String.fromEnvironment('SESSION_ENCRYPTION_SECRET_HEX', defaultValue: '');
  static const String btcsCode = '____BTCS';

}