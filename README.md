# BitcoinSilver Web-Wallet

## Introduction


A modern, secure, and modular web wallet for BitcoinSilver (BTCS). This release provides improved architecture, seed phrase support, and safer RPC communication for web deployment.

<p align="center">
  <img src="assets/logo.png" alt="BitcoinSilver Web-Wallet" width="600">
</p>

<p align="center">
  <strong>The Official Web-Wallet for BitcoinSilver (BTCS)</strong><br>
  Built with Flutter for Web
</p>

<p align="center">
  <a href="https://bitcoinsilver.top">Website</a> •
  <a href="https://explorer.bitcoinsilver.top">Explorer</a>
</p>

## Major Updates in v2.5

### 🪙 Coin Control (Advanced Send)
Full control over which UTXOs are used in a transaction:
- **Advanced tab** in the Send view lets you hand-pick inputs from your confirmed UTXO set.
- **Scrollable UTXO table** with index, truncated TXID:vout, amount, and real confirmation count.
- **Live selection summary**: selected input count and total update instantly as you check/uncheck.
- **Auto-fill amount**: selecting inputs pre-fills the amount field with the exact total.
- **All / None** shortcuts for quick selection.
- Pagination-free — fixed-height scrollable list handles wallets of any size cleanly.

### 💸 Fee Estimation
- **Simple mode**: estimated fee displayed based on a typical 1-in 2-out transaction (226 bytes).
- **Advanced mode**: exact fee estimate recalculated live based on the actual number of selected inputs.
- **Net send** display shows exactly how much the recipient receives after fees.
- Fee rate fetched live from the node via `estimatesmartfee`.

### ✅ Address & Amount Validation
- **Live RPC address validation**: recipient address is verified against the node with a 700ms debounce — green tick on valid, red cross on invalid.
- **Amount guards**: catches negative values, zero, dust threshold violations (< 0.00000546 BTCS), and amounts exceeding selected inputs or available balance.
- **Send button disabled** while validating or when any input error is present — no bad transactions can be fired.

### 📈 Real Confirmation Counts
- UTXO confirmations now calculated accurately from block height (`getblockcount` − UTXO height + 1) instead of being hardcoded.

## Major Updates in v2.4

### 💰 Live price update fetched directly from LiveCoinWatch
- Bitcoin Silver price is aquired directly from LiveCoinWatch and updated every 5 minutes.
- Wallet balance is converted in USD and displayed to keep user informed about price fluctuations.

### 🏗️ Modular Architecture
The project has been refactored from a monolithic structure to a scalable, modular architecture using the **Provider** pattern:
- **Models**: Structured data objects for Wallets and Transactions.
- **Providers**: Centralized state management for UI reactivity.
- **Services**: Dedicated logic for cryptography, storage, and RPC communication.
- **Screens**: Dedicated UI layers for Welcome, Setup, Dashboard, and Network Info.

### 🌱 Seed Phrase Support (BIP39)
Moving beyond raw private keys, the wallet now supports modern **BIP39 Seed Phrases**:
- **Generate 12 or 24 words**: Choose your desired security level.
- **BIP44 Derivation**: Industry-standard derivation paths for maximum compatibility.
- **Secure Backup UI**: Dedicated interface to ensure users save their phrases correctly.

### 🔄 WIF-to-Seed Migration (Sweep)
A unique tool to help legacy users upgrade to modern security:
- **Automatic Sweep**: Transfer all funds from a legacy WIF key to a new Seed-derived address in one click.
- **Smart Handling**: If the wallet is empty, it upgrades the wallet type instantly without requiring a blockchain transaction.
- **Forced Backup**: Automatically prompts the user to secure their new keys post-migration.

### 📊 Real-time Network Info
A new dashboard to monitor the BTCS network health directly within the wallet:
- **Blockchain Stats**: Height, Difficulty, and Median Time.
- **Mempool Metrics**: Pending transaction count and size.
- **Mining Data**: Global network hashrate with automatic unit conversion (GH/s, TH/s).

### 🛡️ Enhanced Security
- **In-Memory Storage**: Sensitive keys now live only in the application's RAM.
- **Refresh Protection**: Refreshing the browser (F5) now clears the session and logs the user out, preventing "partial state" mnemonic loss.
- **Zero Leaks**: All debug prints and sensitive logs have been removed for production.
- **CORS-Ready RPC**: Improved RPC communication that works seamlessly with secure proxies.

## Features

- **Seed Phrase Wallet**: Modern 12/24 word recovery phrases (Recommended).
- **Legacy WIF Wallet**: Support for existing raw Private Keys (WIF).
- **Send/Receive**: Full transaction support with Bech32 (bs1...) addresses and QR codes.
- **Coin Control**: Advanced UTXO selection for privacy and fee optimization.
- **Glassmorphism UI**: A sleek, dark-themed interface with neon purple and gold accents.

## Security Warning

⚠️ **Web wallets are intended for convenience, not long-term high-value storage.**

- Private keys exist ONLY in memory during your active session.
- Closing the tab or refreshing the page logs you out instantly.
- Always verify the URL is `https://bitcoinsilver.top`.
- For large amounts, always use a desktop or hardware wallet.

## Development

Run locally:
```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```
or
```bash
flutter run -d web-server --web-port 8080 --dart-define-from-file=dart_defines.json
```

## Building for Deployment

Build the web app:
```bash
flutter build web --release --base-href "/web-wallet/" --dart-define-from-file=dart_defines.json
```

## RPC Configuration

The wallet uses an RPC proxy to communicate with BitcoinSilver nodes. By default the project expects a secure proxy endpoint such as `https://bitcoinsilver.eu/btcs-rpc` (or your own proxy).

The proxy must:

- Serve over HTTPS.
- Return a single `Access-Control-Allow-Origin` header matching `https://bitcoinsilver.top` (or the origin you host the wallet from).
- Handle preflight `OPTIONS` requests and forward POST JSON-RPC payloads to an upstream node.

## License

MIT License.
