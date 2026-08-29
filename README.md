# BitcoinSilver Web-Wallet

## Introduction

A modern, secure, non-custodial, client-side signing wallet for the Bitcoin Silver network.

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

## Release Notes

For professional release tracking, detailed version history is maintained in [CHANGELOG.md](CHANGELOG.md).

Latest major release: v2.9

- Optional on-chain message on send, embedded via OP_RETURN (up to 80 bytes) with a byte counter and pre-send review.
- Opt-in batch send flow for large transfers with clear user choice and preview.
- Retry-as-batch option when normal single-transaction send fails under size or input constraints.
- Batch migration consent flow with explicit multiple-TX explanation and safety warnings.
- Improved migration completion handling for partial multi-transaction outcomes.

## 🛡️ Security Architecture

This version marks a major shift in our security model:

- **Client-Side Signing**: Transactions are signed locally in the browser. Private keys (WIF) and seed phrases never touch the network/server.
- **Zero-Trust Broadcast**: The RPC node only receives a signed transaction hex; it never sees your private keys or your balance information.
- **Web Runtime Optimized**: Logic refactored to support strict `dart2js` environment constraints (e.g., custom 64-bit integer handling).

---

## 🏗️ Technical Stack

- **Derivation**: BIP39 Mnemonic Seed / BIP44 Standard Paths.
- **Cryptography**: PointyCastle (RIPEMD160/SHA256).
- **Frontend**: Flutter Web (Optimized for performance).
- **Communication**: JSON-RPC over HTTPS.

## Features

- **Seed Phrase Wallet**: Modern 12/24 word recovery phrases (Recommended).
- **Legacy WIF Wallet**: Support for existing raw Private Keys (WIF).
- **Send/Receive**: Full transaction support with Bech32 (bs1...) addresses and QR codes.
- **On-Chain Messages**: Attach an optional public note (up to 80 bytes) to a send via OP_RETURN.
- **Coin Control**: Advanced UTXO selection for privacy and fee optimization.
- **Glassmorphism UI**: A sleek, dark-themed interface with neon purple and gold accents.

## Security Warning

⚠️ **Web wallets are intended for convenience, not long-term high-value storage.**

- Private keys exist ONLY in memory during your active session.
- Closing the tab or refreshing the page logs you out instantly.
- Always verify the URL is `https://bitcoinsilver.top`.
- For large amounts, always use a desktop or hardware wallet.

## Optional Remembered Session (Encrypted Local Storage)

You can optionally enable "Remember Wallet On This Device" from the Settings tab.

When enabled:

- Wallet session data is encrypted and stored in browser local storage.
- The wallet can auto-restore without re-entering your seed/WIF every time.

Risk notes:

- If this device is compromised (malware/extensions), local encrypted data can still be attacked.
- In web builds, dart-define secrets are extractable from shipped assets; this improves resistance but is not absolute secrecy.
- Never enable remembered sessions on shared/public devices.

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
